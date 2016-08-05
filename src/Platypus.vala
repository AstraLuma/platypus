// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
    BEGIN LICENSE

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

    public class PlatypusApp : Gtk.Application {

        private GLib.List <PlatypusWindow> windows;

        public static string? working_directory = null;

        private static bool print_version = false;
        private static bool show_about_dialog = false;

        public int minimum_width;
        public int minimum_height;

        construct {
            flags |= ApplicationFlags.HANDLES_COMMAND_LINE;
/*            build_data_dir = Build.DATADIR;
            build_pkg_data_dir = Build.PKGDATADIR;
            build_release_name = Build.RELEASE_NAME;
            build_version = Build.VERSION;
            build_version_info = Build.VERSION_INFO;

            Intl.setlocale (LocaleCategory.ALL, "");

            program_name = _("Platypus");
            exec_name = "platypus";
            app_years = "2011-2016";
            app_icon = "utilities-terminal";
            app_launcher = "com.astro73.platypus.desktop";
            application_id = "com.astro73.platypus";
            main_url = "https://github.com/astronouth7303/platypus";
            bug_url = "https://github.com/astronouth7303/platypus/issues";
            help_url = "https://github.com/astronouth7303/platypus/wiki";
            about_authors = { "James Bliss <astronouth7303@gmail.com>",
                              "David Gomes <david@elementaryos.org>",
                              "Mario Guerriero <mario@elementaryos.org>",
                              "Akshay Shekher <voldyman666@gmail.com>" };

            // about_documenters = {"",""};
            about_artists = { "Daniel Foré <daniel@elementaryos.org>" };
            about_translators = _("translator-credits");
            about_license_type = Gtk.License.GPL_3_0;*/
        }

        public PlatypusApp () {
            windows = new GLib.List <PlatypusWindow> ();
        }

        public void new_window () {
            new PlatypusWindow (this).present ();
        }

        public override int command_line (ApplicationCommandLine command_line) {
            // keep the application running until we are done with this commandline
            hold ();
            int res = _command_line (command_line);
            release ();
            return res;
        }

        public override void window_added (Gtk.Window window) {
            windows.append (window as PlatypusWindow);
            base.window_added (window);
        }

        public override void window_removed (Gtk.Window window) {
            windows.remove (window as PlatypusWindow);
            base.window_removed (window);
        }

        private int _command_line (ApplicationCommandLine command_line) {
            var context = new OptionContext ("File");
            context.add_main_entries (entries, "pantheon-terminal");
            context.add_group (Gtk.get_option_group (true));

            string[] args = command_line.get_arguments ();

            try {
                unowned string[] tmp = args;
                context.parse (ref tmp);
            } catch (Error e) {
                stdout.printf ("platypus: ERROR: " + e.message + "\n");
                return 0;
            }

            if (working_directory != null) {
                start_terminal_with_working_directory (working_directory);

            } else if (print_version) {
                stdout.printf ("Platypus %s\n", Constants.VERSION);
                stdout.printf ("Copyright 2016 James Bliss.\n");

            } else {
                new_window ();
            }

            return 0;
        }

        private void start_terminal_with_working_directory (string working_directory) {
            new PlatypusWindow.with_working_directory (this, working_directory);
        }

        private PlatypusWindow? get_last_window () {
            uint length = windows.length ();

            return length > 0 ? windows.nth_data (length - 1) : null;
        }

        static const OptionEntry[] entries = {
            { "version", 'v', 0, OptionArg.NONE, out print_version, N_("Print version info and exit"), null },
            { "about", 'a', 0, OptionArg.NONE, out show_about_dialog, N_("Show about dialog"), null },
            { "working-directory", 'w', 0, OptionArg.FILENAME, ref working_directory, N_("Set shell working directory"), "" },
            { null }
        };

        public static int main (string[] args) {
            var app = new PlatypusApp ();
            return app.run (args);
        }
    }
} // Namespace
