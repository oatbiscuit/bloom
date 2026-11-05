/* day_dialog.vala
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

[GtkTemplate (ui = "/io/github/oatbiscuit/bloom/ui/day_dialog.ui")]
public class Bloom.DayDialog : Adw.Dialog {
    [GtkChild] private unowned Adw.WindowTitle day_title;
    [GtkChild] private unowned Gtk.Button clear_day_btn;
    [GtkChild] private unowned Adw.SwitchRow period_switch;
    [GtkChild] private unowned Adw.ComboRow period_flow;

    // Body
    [GtkChild] private unowned Adw.ComboRow ovulation_test_row;
    [GtkChild] private unowned Adw.SpinRow temp_row;
    [GtkChild] private unowned Adw.ComboRow cervical_mucus_row;
    [GtkChild] private unowned Adw.EntryRow notes_row;

    // Symptoms
    [GtkChild] private unowned Adw.SwitchRow cramps_row;
    [GtkChild] private unowned Adw.SwitchRow bloating_row;
    [GtkChild] private unowned Adw.SwitchRow tenderness_row;
    [GtkChild] private unowned Adw.SwitchRow fatigue_row;
    [GtkChild] private unowned Adw.SwitchRow headache_row;
    [GtkChild] private unowned Adw.SwitchRow mood_row;
    [GtkChild] private unowned Adw.SwitchRow cravings_row;

    public GLib.DateTime selected_date { get; construct; }

    private string date_string;
    private Bloom.Database db;
    public bool data_changed { get; private set; default = false; }

    public DayDialog (GLib.DateTime date) {
        Object (selected_date: date);
    }

    construct {
        day_title.title = selected_date.format ("%B %e, %Y");
        this.date_string = selected_date.format ("%Y-%m-%d");
        if (this.db == null) {
            this.db = Bloom.Database.get_instance ();
        }
        
        clear_day_btn.clicked.connect (() => {
            var dialog = new Adw.AlertDialog (
                _("Clear this day?"),
                _("This will permanently erase all data logged for this date.")
            );

            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("clear", _("Clear"));
            dialog.set_response_appearance ("clear", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response ("cancel");
            dialog.set_close_response ("cancel");

            dialog.response.connect ((response) => {
                if (response == "clear") {
                    db.delete_day (date_string);
                    this.data_changed = true;
                    this.close ();
                }
            });

            dialog.present (this);
        });

        period_switch.active = (db.get_log (date_string, "is_period") == 1);
        period_flow.selected = db.get_log (date_string, "flow");

        ovulation_test_row.selected = db.get_log (date_string, "ovulation_test");
        double temp = db.get_temperature (date_string);
        if (temp > 0.0) {
            temp_row.value = temp;
        }
        cervical_mucus_row.selected = db.get_log (date_string, "cervical_mucus");
        notes_row.text = db.get_notes (date_string);

        cramps_row.active = (db.get_log (date_string, "cramps") == 1);
        bloating_row.active = (db.get_log (date_string, "bloating") == 1);
        tenderness_row.active = (db.get_log (date_string, "tenderness") == 1);
        fatigue_row.active = (db.get_log (date_string, "fatigue") == 1);
        headache_row.active = (db.get_log (date_string, "headache") == 1);
        mood_row.active = (db.get_log (date_string, "mood") == 1);
        cravings_row.active = (db.get_log (date_string, "cravings") == 1);

        period_switch.notify["active"].connect (() => {
            db.save_log (date_string, "is_period", period_switch.active ? 1 : 0);
            this.data_changed = true;
        });

        period_flow.notify["selected"].connect (() => {
            db.save_log (date_string, "flow", (int) period_flow.selected);
            this.data_changed = true;
        });

        ovulation_test_row.notify["selected"].connect (() => {
            db.save_log (date_string, "ovulation_test", (int) ovulation_test_row.selected);
            this.data_changed = true;
        });

        temp_row.notify["value"].connect (() => {
            db.save_temperature (date_string, temp_row.value);
            this.data_changed = true;
        });

        cervical_mucus_row.notify["selected"].connect (() => {
            db.save_log (date_string, "cervical_mucus", (int) cervical_mucus_row.selected);
            this.data_changed = true;
        });

        notes_row.notify["text"].connect (() => {
            db.save_notes (date_string, notes_row.text);
            this.data_changed = true;
        });

        cramps_row.notify["active"].connect (() => {
            db.save_log (date_string, "cramps", cramps_row.active ? 1 : 0);
            this.data_changed = true;
        });

        bloating_row.notify["active"].connect (() => {
            db.save_log (date_string, "bloating", bloating_row.active ? 1 : 0);
            this.data_changed = true;
        });

        tenderness_row.notify["active"].connect (() => {
            db.save_log (date_string, "tenderness", tenderness_row.active ? 1 : 0);
            this.data_changed = true;
        });

        fatigue_row.notify["active"].connect (() => {
            db.save_log (date_string, "fatigue", fatigue_row.active ? 1 : 0);
            this.data_changed = true;
        });

        headache_row.notify["active"].connect (() => {
            db.save_log (date_string, "headache", headache_row.active ? 1 : 0);
            this.data_changed = true;
        });

        mood_row.notify["active"].connect (() => {
            db.save_log (date_string, "mood", mood_row.active ? 1 : 0);
            this.data_changed = true;
        });

        cravings_row.notify["active"].connect (() => {
            db.save_log (date_string, "cravings", cravings_row.active ? 1 : 0);
            this.data_changed = true;
        });
    }
}
