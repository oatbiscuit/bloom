/* preferences.vala
 *
 * Copyright 2026 oatbiscuit
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public delegate void VoidCallback ();

[GtkTemplate (ui = "/io/github/oatbiscuit/bloom/ui/preferences.ui")]
public class Bloom.PreferencesDialog : Adw.PreferencesDialog {
    [GtkChild] private unowned Adw.ComboRow week_start_row;

    [GtkChild] private unowned Adw.SpinRow custom_cycle_row;
    [GtkChild] private unowned Adw.SpinRow custom_period_row;
    [GtkChild] private unowned Adw.SpinRow custom_luteal_row;

    [GtkChild] private unowned Adw.ActionRow db_path_row;
    [GtkChild] private unowned Gtk.Button copy_path_btn;
    [GtkChild] private unowned Adw.ActionRow export_data_row;
    [GtkChild] private unowned Adw.ActionRow import_data_row;
    [GtkChild] private unowned Gtk.Button delete_button;

    private Bloom.Database db;
    private GLib.Settings settings;

    public VoidCallback? on_close_callback = null;

    construct {
        this.db = Bloom.Database.get_instance ();
        this.settings = new GLib.Settings ("io.github.oatbiscuit.bloom");

        custom_cycle_row.value = settings.get_int ("custom-cycle-length");
        custom_period_row.value = settings.get_int ("custom-period-length");
        custom_luteal_row.value = settings.get_int ("custom-luteal-phase");

        string current_start = settings.get_string ("week-start-day");
        week_start_row.selected = (current_start == "sunday") ? 1 : 0;

        custom_cycle_row.notify["value"].connect (() => {
            settings.set_int ("custom-cycle-length", (int) custom_cycle_row.value);
        });

        custom_period_row.notify["value"].connect (() => {
            settings.set_int ("custom-period-length", (int) custom_period_row.value);
        });

        custom_luteal_row.notify["value"].connect (() => {
            settings.set_int ("custom-luteal-phase", (int) custom_luteal_row.value);
        });

        export_data_row.activated.connect (on_export_clicked);
        import_data_row.activated.connect (on_import_clicked);
        delete_button.clicked.connect (on_delete_clicked);

        week_start_row.notify["selected"].connect (() => {
            string val = (week_start_row.selected == 1) ? "sunday" : "monday";
            settings.set_string ("week-start-day", val);
        });

        db_path_row.subtitle = db.db_path;
        
        copy_path_btn.clicked.connect (() => {
            this.get_clipboard ().set_text (db.db_path);
        });

        this.closed.connect (() => {
            if (on_close_callback != null) {
                on_close_callback ();
            }
        });
    }

    private void on_export_clicked () {
        var parent = (Gtk.Window) this.get_root ();
        var dialog = new Gtk.FileDialog () {
            title = _("Save CSV File"),
            initial_name = "bloom_export.csv"
        };

        dialog.save.begin (parent, null, (obj, res) => {
            try {
                var file = dialog.save.end (res);
                string path = file.get_path ();
                db.export_to_csv (path);

                var alert = new Adw.AlertDialog (
                    _("Export Successful"),
                    _("Your data has been saved.")
                );
                alert.add_response ("ok", _("OK"));
                alert.present (parent);

            } catch (Error e) {
                warning ("Export failed: %s", e.message);
            }
        });
    }
    
    private void on_import_clicked () {
        var parent = (Gtk.Window) this.get_root ();
        var dialog = new Gtk.FileDialog () {
            title = _("Import CSV File")
        };
        
        var filter = new Gtk.FileFilter () {
            name = _("CSV Files")
        };
        filter.add_pattern ("*.csv");
        
        var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
        filters.append (filter);
        dialog.filters = filters;

        dialog.open.begin (parent, null, (obj, res) => {
            try {
                var file = dialog.open.end (res);
                string path = file.get_path ();
                
                string error_msg;
                bool success = db.import_from_csv (path, out error_msg);

                var alert = new Adw.AlertDialog (
                    success ? _("Import Successful") : _("Import Failed"),
                    success ? _("Your data has been imported.") : error_msg
                );
                alert.add_response ("ok", _("OK"));
                
                if (success) {
                    if (on_close_callback != null) {
                        on_close_callback ();
                    }
                }
                
                alert.present (parent);

            } catch (Error e) {
                warning ("Import failed: %s", e.message);
            }
        });
    }

    private void on_delete_clicked () {
        var dialog = new Adw.AlertDialog (
            _("Delete All Data?"),
            _("This will permanently erase all your logged cycles and symptoms. This action cannot be undone.")
        );

        dialog.add_response ("cancel", _("Cancel"));
        dialog.add_response ("delete", _("Delete"));
        dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response ("cancel");
        dialog.set_close_response ("cancel");

        dialog.response.connect ((response) => {
            if (response == "delete") {
                db.delete_all_data ();

                var success = new Adw.AlertDialog (
                    _("Data Deleted"),
                    _("All your data has been successfully removed.")
                );
                success.add_response ("ok", _("OK"));
                success.present (this);
            }
        });

        dialog.present (this);
    }
}
