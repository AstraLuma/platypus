// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
    BEGIN LICENSE

    Copyright (C) 2016 James Bliss
    Copyright (C) 2011-2014 Pantheon Terminal Developers
    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU Lesser General Public License version 3, as published
    by the Free Software Foundation.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranties of
    MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
    PURPOSE.  See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program.  If not, see <http://www.gnu.org/licenses/>

    END LICENSE
 ***/

namespace Platypus {

    public class TerminalWidget : Vte.Terminal {
        enum DropTargets {
            URILIST,
            STRING,
            TEXT
        }


        public string terminal_id;
        static int terminal_id_counter = 0;
        private bool init_complete;

        GLib.Pid child_pid;
        private PlatypusWindow _window;

        public PlatypusWindow window {
            get {
                return _window;
            }

            set {
                this._window = value;
                this.menu = value.ui.get_widget ("ui/AppMenu") as Gtk.Menu;
                this.menu.show_all ();
            }
        }

        private Gtk.Menu menu;
        public string? uri;

        public int default_size;
        public double zoom_factor = 1.0;

        /* Following strings are used to build RegEx for matching URIs */
        const string USERCHARS = "-[:alnum:]";
        const string USERCHARS_CLASS = "[" + USERCHARS + "]";
        const string PASSCHARS_CLASS = "[-[:alnum:]\\Q,?;.:/!%$^*&~\"#'\\E]";
        const string HOSTCHARS_CLASS = "[-[:alnum:]]";
        const string HOST = HOSTCHARS_CLASS + "+(\\." + HOSTCHARS_CLASS + "+)*";
        const string PORT = "(?:\\:[[:digit:]]{1,5})?";
        const string PATHCHARS_CLASS = "[-[:alnum:]\\Q_$.+!*,;:@&=?/~#%\\E]";
        const string PATHTERM_CLASS = "[^\\Q]'.}>) \t\r\n,\"\\E]";
        const string SCHEME = """(?:news:|telnet:|nntp:|file:\/|https?:|ftps?:|sftp:|webcal:
                                 |irc:|sftp:|ldaps?:|nfs:|smb:|rsync:|ssh:|rlogin:|telnet:|git:
                                 |git\+ssh:|bzr:|bzr\+ssh:|svn:|svn\+ssh:|hg:|mailto:|magnet:)""";

        const string USERPASS = USERCHARS_CLASS + "+(?:" + PASSCHARS_CLASS + "+)?";
        const string URLPATH = "(?:(/" + PATHCHARS_CLASS + "+(?:[(]" + PATHCHARS_CLASS + "*[)])*" + PATHCHARS_CLASS + "*)*" + PATHTERM_CLASS + ")?";

        static const string[] regex_strings = {
            SCHEME + "//(?:" + USERPASS + "\\@)?" + HOST + PORT + URLPATH,
            "(?:www|ftp)" + HOSTCHARS_CLASS + "*\\." + HOST + PORT + URLPATH,
            "(?:callto:|h323:|sip:)" + USERCHARS_CLASS + "[" + USERCHARS + ".]*(?:" + PORT + "/[a-z0-9]+)?\\@" + HOST,
            "(?:mailto:)?" + USERCHARS_CLASS + "[" + USERCHARS + ".]*\\@" + HOSTCHARS_CLASS + "+\\." + HOST,
            "(?:news:|man:|info:)[[:alnum:]\\Q^_{|}~!\"#$%&'()*+,./;:=?`\\E]+"
        };

        public bool child_has_exited {
            get;
            private set;
        }

        public bool killed {
            get;
            private set;
        }

        public TerminalWidget (PlatypusWindow parent_window) {

            terminal_id = "%i".printf (terminal_id_counter++);

            init_complete = false;

            window = parent_window;
            child_has_exited = false;
            killed = false;

            /* Connect to necessary signals */
            button_press_event.connect ((event) => {
                uri = get_link ((long) event.x, (long) event.y);

                switch (event.button) {
                    case Gdk.BUTTON_PRIMARY:
                        if (uri != null) {
                            try {
                                Gtk.show_uri (null, (!) uri, Gtk.get_current_event_time ());
                                return true;
                            } catch (GLib.Error error) {
                                warning ("Could Not Open link");
                            }
                        }

                        return false;
                    case Gdk.BUTTON_SECONDARY:
                        if (uri != null) {
                            window.main_actions.get_action ("Copy").set_sensitive (true);
                        }

                        menu.select_first (false);
                        menu.popup (null, null, null, event.button, event.time);

                        return true;
                }

                return false;
            });

            selection_changed.connect (() => {
                window.main_actions.get_action ("Copy").set_sensitive (get_has_selection ());
            });

            window_title_changed.connect ((event) => {
                window.title = window_title;
            });

            child_exited.connect (on_child_exited);

            /* target entries specify what kind of data the terminal widget accepts */
            Gtk.TargetEntry uri_entry = { "text/uri-list", Gtk.TargetFlags.OTHER_APP, DropTargets.URILIST };
            Gtk.TargetEntry string_entry = { "STRING", Gtk.TargetFlags.OTHER_APP, DropTargets.STRING };
            Gtk.TargetEntry text_entry = { "text/plain", Gtk.TargetFlags.OTHER_APP, DropTargets.TEXT };

            Gtk.TargetEntry[] targets = { };
            targets += uri_entry;
            targets += string_entry;
            targets += text_entry;

            Gtk.drag_dest_set (this, Gtk.DestDefaults.ALL, targets, Gdk.DragAction.COPY);

            /* Make Links Clickable */
            this.drag_data_received.connect (drag_received);
            this.clickable (regex_strings);
        }

        void on_child_exited () {
            child_has_exited = true;
        }

        public void kill_fg () {
            int fg_pid;
            if (this.try_get_foreground_pid (out fg_pid))
                Posix.kill (fg_pid, Posix.SIGKILL);
        }

        public void term_ps () {
            killed = true;

            /* Check if the shell process is still alive by sending 0 signals */
            while (Posix.kill (this.child_pid, 0) == 0) {
                Posix.kill (this.child_pid, Posix.SIGHUP);
                Posix.kill (this.child_pid, Posix.SIGTERM);
                Thread.usleep (100);
            }
        }

        public void active_shell (string dir = GLib.Environment.get_current_dir ()) {
            string shell = Vte.get_user_shell ();
            string?[] envv = null;

            envv = {
                // Export ID so we can identify the terminal for which the process completion is reported
                "PLATYPUS_TERMINAL_ID=" + terminal_id,
            };

            /* Putting this in an Idle loop helps avoid corruption of the prompt on startup with multiple tabs */
            Idle.add_full (GLib.Priority.LOW, () => {
                try {
                    this.spawn_sync (Vte.PtyFlags.DEFAULT, dir, { shell },
                                            envv, SpawnFlags.SEARCH_PATH, null, out this.child_pid, null);
                } catch (Error e) {
                    warning (e.message);
                }
                return false;
            });
        }

        public void run_program (string program_string) {
            try {
                string[]? program_with_args = null;
                Shell.parse_argv (program_string, out program_with_args);

                this.spawn_sync (Vte.PtyFlags.DEFAULT, null, program_with_args,
                                        null, SpawnFlags.SEARCH_PATH, null, out this.child_pid, null);
            } catch (Error e) {
                warning (e.message);
            }
        }

        public bool try_get_foreground_pid (out int pid) {
            if (child_has_exited) {
                pid = -1;
                return false;
            }

            int pty = get_pty().fd;
            int fgpid = Posix.tcgetpgrp (pty);

            if (fgpid != this.child_pid && fgpid != -1) {
                pid = (int) fgpid;
                return true;
            } else {
                pid = -1;
                return false;
            }
        }

        public bool has_foreground_process () {
            return try_get_foreground_pid (null);
        }

        public int calculate_width (int column_count) {
            int width = (int) (this.get_char_width ()) * column_count;
            return width;
        }

        public int calculate_height (int row_count) {
            int height = (int) (this.get_char_height ()) * row_count;
            return height;
        }

        private void clickable (string[] str) {
            foreach (string exp in str) {
                try {
                    var regex = new GLib.Regex (exp);
                    int id = this.match_add_gregex (regex, 0);

                    this.match_set_cursor_type (id, Gdk.CursorType.HAND2);
                } catch (GLib.RegexError error) {
                    warning (error.message);
                }
            }
        }

        private string? get_link (long x, long y) {
            long col = x / this.get_char_width ();
            long row = y / this.get_char_height ();
            int tag;

            // Vte.Terminal.match_check need a non-null tag instead of what is
            // written in the doc
            // (see: https://bugzilla.gnome.org/show_bug.cgi?id=676886)
            return this.match_check (col, row, out tag);
        }

        public string get_shell_location () {
            int pid = (!) (this.child_pid);

            try {
                return GLib.FileUtils.read_link ("/proc/%d/cwd".printf (pid));
            } catch (GLib.FileError error) {
                warning ("An error occured while fetching the current dir of shell");
                return "";
            }
        }

        public void increment_size () {
            Pango.FontDescription current_font = this.get_font ();
            if (default_size == 0) default_size = current_font.get_size ();
            if (current_font.get_size () > 60000) return;

            zoom_factor += 0.1;
            current_font.set_size ((int) Math.floor (default_size * zoom_factor));
            this.set_font (current_font);
        }

        public void decrement_size () {
            Pango.FontDescription current_font = this.get_font ();
            if (default_size == 0) default_size = current_font.get_size ();
            if (current_font.get_size () < 2048) return;

            zoom_factor -= 0.1;
            current_font.set_size ((int) Math.ceil (default_size * zoom_factor));
            this.set_font (current_font);
        }

        public void set_default_font_size () {
            Pango.FontDescription current_font = this.get_font ();
            if (default_size == 0) default_size = current_font.get_size ();

            zoom_factor = 1.0;
            current_font.set_size (default_size);
            this.set_font (current_font);
        }

        public bool is_init_complete () {
            return init_complete;
        }

        public void set_init_complete () {
            init_complete = true;
        }

        public void drag_received (Gdk.DragContext context, int x, int y,
                                   Gtk.SelectionData selection_data, uint target_type, uint time_) {
            switch (target_type) {
                case DropTargets.URILIST:
                    var uris = selection_data.get_uris ();
                    string path;
                    File file;

                    for (var i = 0; i < uris.length; i++) {
                         file = File.new_for_uri (uris[i]);
                         if ((path = file.get_path ()) != null) {
                             uris[i] = Shell.quote (path) + " ";
                        }
                    }

                    string uris_s = string.joinv ("", uris);
                    this.feed_child (uris_s, uris_s.length);

                    break;
                case DropTargets.STRING:
                case DropTargets.TEXT:
                    var data = selection_data.get_text ();

                    if (data != null) {
                        this.feed_child (data, data.length);
                    }

                    break;
            }
        }
    }
}
