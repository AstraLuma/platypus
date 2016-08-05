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

    public class PlatypusWindow : Gtk.Window {

        public PlatypusApp app {
            get {
                return application as PlatypusApp;
            }
        }

        Pango.FontDescription term_font;
        private Gtk.Clipboard clipboard;
        private Platypus.Widgets.SearchToolbar search_toolbar;
        private Gtk.Revealer search_revealer;
        public Gtk.ToggleButton search_button;

        public TerminalWidget terminal;

        const string ui_string = """
            <ui>
            <popup name="MenuItemTool">
                <menuitem name="New window" action="New window"/>
                <menuitem name="Copy" action="Copy"/>
                <menuitem name="Paste" action="Paste"/>
                <menuitem name="Select All" action="Select All"/>
                <menuitem name="Search" action="Search"/>
                <menuitem name="About" action="About"/>

                <menuitem name="NextTab" action="NextTab"/>
                <menuitem name="PreviousTab" action="PreviousTab"/>

                <menuitem name="ZoomIn" action="ZoomIn"/>
                <menuitem name="ZoomOut" action="ZoomOut"/>

                <menuitem name="Fullscreen" action="Fullscreen"/>
            </popup>

            <popup name="AppMenu">
                <menuitem name="Copy" action="Copy"/>
                <menuitem name="Paste" action="Paste"/>
                <menuitem name="Select All" action="Select All"/>
                <menuitem name="Search" action="Search"/>
            </popup>
            </ui>
        """;

        public Gtk.ActionGroup main_actions;
        public Gtk.UIManager ui;

        public bool unsafe_ignored;

        public PlatypusWindow (PlatypusApp app) {
            init (app);
        }

        public PlatypusWindow.with_working_directory (PlatypusApp app, string location) {
            init (app);
            initterm (location);
        }

        private void init (PlatypusApp app) {
            icon_name = "utilities-terminal";
            set_application (app);


            Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;

            set_visual (Gdk.Screen.get_default ().get_rgba_visual ());

            title = _("Terminal");

            /* Actions and UIManager */
            app.add_action_entries (main_entries, this);

            clipboard = Gtk.Clipboard.get (Gdk.Atom.intern ("CLIPBOARD", false));
            update_context_menu ();
            clipboard.owner_change.connect (update_context_menu);

            ui = new Gtk.UIManager ();

            try {
                ui.add_ui_from_string (ui_string, -1);
            } catch (Error e) {
                error ("Couldn't load the UI: %s", e.message);
            }

            Gtk.AccelGroup accel_group = ui.get_accel_group ();
            add_accel_group (accel_group);

            ui.insert_action_group (main_actions, 0);
            ui.ensure_update ();

            setup_ui ();
            show_all ();

            this.search_revealer.set_reveal_child (false);
            term_font = Pango.FontDescription.from_string (get_term_font ());

            set_size_request (app.minimum_width, app.minimum_height);

            search_button.toggled.connect (on_toggle_search);
        }

        /** Returns true if the code parameter matches the keycode of the keyval parameter for
          * any keyboard group or level (in order to allow for non-QWERTY keyboards) **/
        protected bool match_keycode (int keyval, uint code) {
            Gdk.KeymapKey [] keys;
            Gdk.Keymap keymap = Gdk.Keymap.get_default ();
            if (keymap.get_entries_for_keyval (keyval, out keys)) {
                foreach (var key in keys) {
                    if (code == key.keycode)
                        return true;
                }
            }

            return false;
        }

        private void setup_ui () {
            /* Use CSD */
            var header = new Gtk.HeaderBar ();
            header.set_show_close_button (true);
            header.get_style_context ().add_class ("compact");

            this.set_titlebar (header);

            search_button = new Gtk.ToggleButton ();
            var img = new Gtk.Image.from_icon_name ("edit-find-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
            search_button.set_image (img);
            search_button.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);
            search_button.set_tooltip_text (_("Find…"));
            header.pack_end (search_button);

            var grid = new Gtk.Grid ();
            this.search_toolbar = new Platypus.Widgets.SearchToolbar (this);
            this.search_revealer = new Gtk.Revealer ();
            this.search_revealer.set_transition_type (Gtk.RevealerTransitionType.SLIDE_DOWN);
            this.search_revealer.add (this.search_toolbar);

            grid.attach (this.search_revealer, 0, 0, 1, 1);

            main_actions.get_action ("Copy").set_sensitive (false);

            add (grid);

            // FIXME: Use accelerators?
            key_press_event.connect ((e) => {
                switch (e.keyval) {
                    case Gdk.Key.Escape:
                        if (this.search_toolbar.search_entry.has_focus) {
                            this.search_button.active = !this.search_button.active;
                            return true;
                        }
                        break;
                    case Gdk.Key.KP_Add:
                        if ((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                            action_zoom_in_font ();
                            return true;
                        }
                        break;
                    case Gdk.Key.KP_Subtract:
                        if ((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                            action_zoom_out_font ();
                            return true;
                        }
                        break;
                    case Gdk.Key.Return:
                        if (this.search_toolbar.search_entry.has_focus) {
                            if ((e.state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                                this.search_toolbar.previous_search ();
                            } else {
                                this.search_toolbar.next_search ();
                            }
                            return true;
                        }
                        break;
                    case Gdk.Key.@0:
                        if ((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                            action_zoom_default_font ();
                            return true;
                        }
                        break;
                }

                return false;
            });
        }

        private void on_toggle_search () {

            var is_search = this.search_button.get_active ();

            this.search_revealer.set_reveal_child (is_search);
            if (is_search) {
                search_toolbar.grab_focus ();
            } else {
                this.search_toolbar.clear ();
                this.terminal.grab_focus ();
            }
        }

        private void update_context_menu () {
            clipboard.request_targets (update_context_menu_cb);
        }

        private void update_context_menu_cb (Gtk.Clipboard clipboard_,
                                             Gdk.Atom[] atoms) {
            bool can_paste = false;

            if (atoms != null && atoms.length > 0)
                can_paste = Gtk.targets_include_text (atoms) || Gtk.targets_include_uri (atoms);

            main_actions.get_action ("Paste").set_sensitive (can_paste);
        }

        private void initterm (string directory, string? program = null) {
            /*
             * If the user choose to use a specific working directory.
             * Reassigning the directory variable a new value
             * leads to free'd memory being read.
             */
            string location;
            if (directory == "") {
                location = PlatypusApp.working_directory ?? Environment.get_current_dir ();
            } else {
                location = directory;
            }

            /* Set up terminal */
            var t = new TerminalWidget (this);

            /* Make the terminal occupy the whole GUI */
            t.vexpand = true;
            t.hexpand = true;


            t.set_font (term_font);

            int minimum_width = t.calculate_width (80) / 2;
            int minimum_height = t.calculate_height (24) / 2;
            set_size_request (minimum_width, minimum_height);
            app.minimum_width = minimum_width;
            app.minimum_height = minimum_height;

            Gdk.Geometry hints = Gdk.Geometry();
            hints.width_inc = (int) t.get_char_width ();
            hints.height_inc = (int) t.get_char_height ();
            set_geometry_hints (this, hints, Gdk.WindowHints.RESIZE_INC);

            t.grab_focus ();

            if (program == null) {
                /* Set up the virtual terminal */
                if (location == "") {
                    t.active_shell ();
                } else {
                    t.active_shell (location);
                }
            } else {
                t.run_program (program);
            }
        }

        static string get_term_font () {
            string font_name;

            var settings_sys = new GLib.Settings ("org.gnome.desktop.interface");
            font_name = settings_sys.get_string ("monospace-font-name");

            return font_name;
        }

        protected override bool delete_event (Gdk.EventAny event) {
            action_quit ();

            if (terminal.has_foreground_process ()) {
                var d = new ForegroundProcessDialog.before_close ();
                if (d.run () == 1) {
                    terminal.kill_fg ();
                    d.destroy ();
                } else {
                    d.destroy ();
                    return true;
                }
            }

            terminal.term_ps ();

            return false;
        }

        void on_get_text (Gtk.Clipboard board, string? intext) {
            terminal.paste_clipboard();
        }

        void action_quit () {

        }

        void action_copy () {
            if (terminal.uri != null)
                clipboard.set_text (terminal.uri,
                                    terminal.uri.length);
            else
                terminal.copy_clipboard ();
        }

        void action_paste () {
            clipboard.request_text (on_get_text);
        }

        void action_select_all () {
            terminal.select_all ();
        }

        void action_new_window () {
            app.new_window ();
        }

        void action_about () {
            //app.show_about (this);
        }

        void action_zoom_in_font () {
            terminal.increment_size ();
        }

        void action_zoom_out_font () {
            terminal.decrement_size ();
        }

        void action_zoom_default_font () {
            terminal.set_default_font_size ();
        }

        void action_search () {
            this.search_button.active = !this.search_button.active;
        }

        static const GLib.ActionEntry[] main_entries = {
            { "New window", action_new_window }, //"window-new", N_("New Window"), "<Control><Shift>n", N_("Open a new window"),
            { "Copy", action_copy }, // "gtk-copy", N_("Copy"), "<Control><Shift>c", N_("Copy the selected text"),
            { "Search", action_search }, // "edit-find", N_("Find…"), "<Control><Shift>f", N_("Search for a given string in the terminal"),
            { "Paste", action_paste }, // "gtk-paste", N_("Paste"), "<Control><Shift>v", N_("Paste some text"),
            { "Select All", action_select_all }, // "gtk-select-all", N_("Select All"), "<Control><Shift>a", N_("Select all the text in the terminal"),
            { "About", action_about }, // "gtk-about", N_("About"), null, N_("Show about window"),
            { "ZoomIn", action_zoom_in_font }, // "gtk-zoom-in", N_("Zoom in"), "<Control>plus", N_("Zoom in"),
            { "ZoomOut", action_zoom_out_font }, // "gtk-zoom-out", // N_("Zoom out"), "<Control>minus", N_("Zoom out"),
        };
    }
}
