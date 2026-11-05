/* window.vala
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

[GtkTemplate (ui = "/io/github/oatbiscuit/bloom/ui/window.ui")]
public class Bloom.Window : Adw.ApplicationWindow {
    [GtkChild] private unowned Adw.ViewSwitcher view_switcher;
    [GtkChild] private unowned Adw.ViewStack view_stack;

    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Gtk.Button prev_month_btn;
    [GtkChild] private unowned Gtk.Button next_month_btn;
    [GtkChild] private unowned Gtk.MenuButton jump_to_date_btn;
    [GtkChild] private unowned Gtk.Calendar jump_calendar;
    [GtkChild] private unowned Gtk.Label month_label;
    [GtkChild] private unowned Gtk.Grid calendar_grid;
    [GtkChild] private unowned Adw.ActionRow cycle_day_row;
    [GtkChild] private unowned Adw.ActionRow next_period_row;

    [GtkChild] private unowned Gtk.DropDown year_dropdown;
    [GtkChild] private unowned Gtk.DrawingArea heatmap_area;
    [GtkChild] private unowned Adw.ActionRow avg_cycle_row;
    [GtkChild] private unowned Adw.ActionRow med_cycle_row;
    [GtkChild] private unowned Adw.ActionRow avg_period_row;
    [GtkChild] private unowned Adw.ActionRow med_period_row;
    [GtkChild] private unowned Adw.ActionRow total_cycles_row;
    [GtkChild] private unowned Adw.ActionRow all_time_cycle_row;
    [GtkChild] private unowned Adw.ActionRow all_time_period_row;
    [GtkChild] private unowned Gtk.Label regularity_label;
    
    [GtkChild] private unowned Gtk.SearchEntry search_notes_entry;
    [GtkChild] private unowned Adw.PreferencesGroup notes_group;

    private GLib.DateTime current_month;
    private Bloom.Database db;
    private Bloom.CycleEngine engine;
    private GLib.Settings settings;

    construct {
        db = Bloom.Database.get_instance();
        engine = new Bloom.CycleEngine ();
        this.settings = new GLib.Settings ("io.github.oatbiscuit.bloom");

        view_switcher.stack = view_stack;

        calendar_grid.add_css_class ("calendar_grid");

        view_stack.notify["visible-child"].connect (() => {
            bool is_calendar = (view_stack.visible_child_name == "calendar");
            bool is_notes = (view_stack.visible_child_name == "notes");

            prev_month_btn.visible = is_calendar;
            next_month_btn.visible = is_calendar;
            jump_to_date_btn.visible = is_calendar;
            month_label.visible = is_calendar;

            if (view_stack.visible_child_name == "insights") {
                update_insights ();
            } else if (is_notes) {
                update_notes_view (search_notes_entry.text);
            }
        });
        
        search_notes_entry.search_changed.connect (() => {
            update_notes_view (search_notes_entry.text);
        });

        prev_month_btn.clicked.connect (() => {
            current_month = current_month.add_months (-1);
            rebuild_grid ();
        });

        next_month_btn.clicked.connect (() => {
            current_month = current_month.add_months (1);
            rebuild_grid ();
        });

        jump_calendar.day_selected.connect (() => {
            var selected_date = jump_calendar.get_date ();
            
            current_month = new GLib.DateTime.local (
                selected_date.get_year (),
                selected_date.get_month (),
                1, 0, 0, 0
            );

            rebuild_grid ();

            jump_to_date_btn.popover.popdown ();
        });

        heatmap_area.set_draw_func (draw_heatmap);
        
        // Populate the year dropdown
        var years = db.get_years_with_data ();
        var year_strings = new Gtk.StringList (null);
        foreach (int y in years) {
            year_strings.append (y.to_string ());
        }
        year_dropdown.model = year_strings;

        // Redraw when the year changes
        year_dropdown.notify["selected"].connect (() => {
            heatmap_area.queue_draw ();
        });

        current_month = new GLib.DateTime.now_local ();
        rebuild_grid ();
    }

    public Window (Gtk.Application app) {
        Object (application: app);
    }

    public void rebuild_grid () {
        Gtk.Widget? child = calendar_grid.get_first_child ();

        while (child != null) {
            var next = child.get_next_sibling ();
            calendar_grid.remove (child);
            child = next;
        }

        update_month_label ();
        update_cycle_info ();

        string week_start = settings.get_string ("week-start-day");
        bool is_sunday_start = (week_start == "sunday");

        string[] day_names;

        if (is_sunday_start) {
            day_names = { _("Sun"), _("Mon"), _("Tues"), _("Wed"), _("Thu"), _("Fri"), _("Sat") };
        } else {
            day_names = { _("Mon"), _("Tues"), _("Wed"), _("Thu"), _("Fri"), _("Sat"), _("Sun") };
        }

        for (int col = 0; col < 7; col++) {
            var label = new Gtk.Label (day_names[col]);
            label.add_css_class ("dim-label");
            label.add_css_class ("caption");
            calendar_grid.attach (label, col, 0, 1, 1);
        }

        var first = new GLib.DateTime.local (
            current_month.get_year (),
            current_month.get_month (),
            1, 0, 0, 0
        );

        int weekday = first.get_day_of_week ();
        int offset;

        if (is_sunday_start) {
            offset = weekday % 7;
        } else {
            offset = weekday - 1;
        }

        var grid_start = first.add_days (-offset);

        var predicted_periods = engine.get_predicted_periods (current_month);
        var predicted_ovulations = engine.get_predicted_ovulation (current_month);

        var day = grid_start;
        for (int row = 1; row <= 6; row++) {
            for (int col = 0; col < 7; col++) {
                var btn = new Gtk.Button.with_label (day.get_day_of_month ().to_string ());
                btn.add_css_class ("flat");
                btn.hexpand = false;
                btn.vexpand = true;
                btn.halign = Gtk.Align.CENTER;
                btn.valign = Gtk.Align.CENTER;
                btn.width_request = 64;
                btn.height_request = 64;

                var date_string = day.format ("%Y-%m-%d");
                bool is_actual_period = is_period_day (day);
                var tooltip_lines = new Gee.ArrayList<string> ();
                tooltip_lines.add (day.format ("%B %d, %Y"));

                if (day.get_month () != current_month.get_month ()) {
                    btn.add_css_class ("dim-label");
                }

                if (is_actual_period) {
                    btn.add_css_class ("period_day");
                    tooltip_lines.add (_("Period Day"));
                } else if (predicted_periods.contains (date_string)) {
                    btn.add_css_class ("predicted_period_day");
                    tooltip_lines.add (_("Predicted Period"));
                }

                if (predicted_ovulations.contains (date_string)) {
                    btn.add_css_class ("ovulation_day");
                    tooltip_lines.add (_("Predicted Ovulation"));
                }

                if (is_today (day)) {
                    btn.add_css_class ("today");
                    tooltip_lines.add (_("Today"));
                }

                btn.tooltip_text = string.joinv ("\n", tooltip_lines.to_array ());

                var captured = day;
                btn.clicked.connect (() => on_day_clicked (captured));

                calendar_grid.attach (btn, col, row, 1, 1);
                day = day.add_days (1);
            }
        }
    }

    private bool is_today (GLib.DateTime d) {
        var now = new GLib.DateTime.now_local ();
        return d.get_year () == now.get_year ()
            && d.get_month () == now.get_month ()
            && d.get_day_of_month () == now.get_day_of_month ();
    }

    private bool is_period_day (GLib.DateTime d) {
        string date_string = d.format ("%Y-%m-%d");

        return db.get_log (date_string, "is_period") == 1;
    }

    private void update_month_label () {
        month_label.label = current_month.format ("%B %Y");
    }

    private void update_cycle_info () {
        var today = new GLib.DateTime.now_local ();
        int cycle_day = engine.get_current_cycle_day (today);
        var next_period = engine.get_next_period_date ();

        if (cycle_day == 0) {
            cycle_day_row.subtitle = _("No data logged yet");
            next_period_row.subtitle = _("Log your first period to see predictions");
            return;
        }
        
        int period_length = engine.get_median_period_length ();
        int cycle_length = engine.get_median_cycle_length ();
        
        int luteal_length = settings.get_int ("custom-luteal-phase");
        if (luteal_length <= 0) luteal_length = 14;
        
        string phase = get_cycle_phase (cycle_day, period_length, cycle_length, luteal_length);

        cycle_day_row.subtitle = _(@"Day $cycle_day ($phase)");

        if (next_period != null) {
            var diff = next_period.difference (today);
            int days_until = (int) (diff / TimeSpan.DAY);

            string date_str = next_period.format ("%B %d");

            if (days_until < 0) {
                next_period_row.subtitle = _("Expected. Log it when it starts.");
            } else if (days_until == 0) {
                next_period_row.subtitle = _("Expected today");
            } else {
                next_period_row.subtitle = _(@"$date_str (in $days_until days)");
            }
        } else {
            next_period_row.subtitle = _("Unknown");
        }
    }

    private void update_insights () {
        int avg_cycle = engine.get_average_cycle_length ();
        int med_cycle = engine.get_median_cycle_length ();
        int avg_period = engine.get_average_period_length ();
        int med_period = engine.get_median_period_length ();

        var starts = engine.get_cycle_start_dates ();
        int total_cycles = starts.size;

        avg_cycle_row.subtitle = _(@"$avg_cycle days");
        med_cycle_row.subtitle = _(@"$med_cycle days");
        avg_period_row.subtitle = _(@"$avg_period days");
        med_period_row.subtitle = _(@"$med_period days");
        total_cycles_row.subtitle = _(@"$total_cycles");

        int all_time_avg_cycle = engine.get_all_time_average_cycle_length ();
        int all_time_avg_period = engine.get_all_time_average_period_length ();
        all_time_cycle_row.subtitle = _(@"$all_time_avg_cycle days");
        all_time_period_row.subtitle = _(@"$all_time_avg_period days");

        string reg_text = engine.get_regularity_label ();
        regularity_label.label = reg_text;

        regularity_label.remove_css_class ("success");
        regularity_label.remove_css_class ("warning");
        regularity_label.remove_css_class ("error");
        regularity_label.remove_css_class ("dim-label");

        if (reg_text == _("Very Regular")) {
            regularity_label.add_css_class ("success");
            regularity_label.add_css_class ("caption");
        } else if (reg_text == _("Regular")) {
            regularity_label.add_css_class ("caption");
        } else if (reg_text == _("Irregular")) {
            regularity_label.add_css_class ("warning");
            regularity_label.add_css_class ("caption");
        } else {
            regularity_label.add_css_class ("dim-label");
            regularity_label.add_css_class ("caption");
        }

        if (total_cycles == 0) {
            avg_cycle_row.subtitle = _("No data yet");
            med_cycle_row.subtitle = _("No data yet");
            avg_period_row.subtitle = _("No data yet");
            med_period_row.subtitle = _("No data yet");
            all_time_cycle_row.subtitle = _("No data yet");
            all_time_period_row.subtitle = _("No data yet");
            total_cycles_row.subtitle = _("0");
            regularity_label.label = _("Not enough data");
            regularity_label.remove_css_class ("success");
            regularity_label.remove_css_class ("warning");
            regularity_label.add_css_class ("dim-label");
        }
    }
    
    private Gee.ArrayList<Adw.ActionRow> note_rows = new Gee.ArrayList<Adw.ActionRow> ();

    private void update_notes_view (string search_term) {
        foreach (var row in note_rows) {
            notes_group.remove (row);
        }
        note_rows.clear ();

        var notes_map = db.search_notes (search_term);

        if (notes_map.size == 0) {
            var empty_row = new Adw.ActionRow () {
                title = _("No notes found"),
                subtitle = _("Try a different search term.")
            };
            notes_group.add (empty_row);
            note_rows.add (empty_row);
            return;
        }

        foreach (var entry in notes_map.entries) {
            string date_str = entry.key;
            string note = entry.value;

            var dt = new GLib.DateTime.from_iso8601 (date_str + "T00:00:00Z", null);
            string formatted_date = dt.format ("%B %e, %Y");

            var row = new Adw.ActionRow () {
                title = formatted_date,
                subtitle = note,
                activatable = true
            };

            row.activated.connect (() => {
                current_month = new GLib.DateTime.local (
                    dt.get_year (), dt.get_month (), 1, 0, 0, 0
                );
                rebuild_grid ();
                view_stack.visible_child_name = "calendar";
            });

            notes_group.add (row);
            note_rows.add (row);
        }
    }

    private void on_day_clicked (GLib.DateTime date) {
        var dialog = new Bloom.DayDialog (date);
        dialog.closed.connect (() => {
            rebuild_grid ();

            if (dialog.data_changed) {
                string date_str = date.format ("%B %d, %Y");
                var toast = new Adw.Toast (_(@"Changes saved for $date_str"));
                toast.timeout = 2;
                toast_overlay.add_toast (toast);
            }
        });
        dialog.present (this);
    }
    
    private string get_cycle_phase (int cycle_day, int period_length, int cycle_length, int luteal_length) {
        int ovulation_day = cycle_length - luteal_length;

        if (cycle_day <= period_length) {
            return _("Menstruation");
        } else if (cycle_day < ovulation_day) {
            return _("Follicular");
        } else if (cycle_day == ovulation_day) {
            return _("Ovulation");
        } else {
            return _("Luteal");
        }
    }
    
    private void draw_heatmap (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        uint year_idx = year_dropdown.selected;
        if (year_idx == Gtk.INVALID_LIST_POSITION) return;
        
        var string_obj = year_dropdown.selected_item as Gtk.StringObject;
        if (string_obj == null) return;
        string year_str = string_obj.get_string ();
        int year = int.parse (year_str);

        var data = db.get_year_period_days (year);

        int num_cols = 53; 
        int spacing = 2; 
        
        int cell_size = (int) (((double) width - (num_cols - 1) * spacing) / num_cols);
        if (cell_size > 16) cell_size = 16;
        if (cell_size < 6) cell_size = 6;

        var start_date = new GLib.DateTime.local (year, 1, 1, 0, 0, 0);
        int start_weekday = start_date.get_day_of_week ();
        int start_offset = start_weekday - 1;

        double start_y = 20.0; 

        cr.set_source_rgba (0.5, 0.5, 0.5, 1.0);
        cr.select_font_face ("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
        cr.set_font_size (10);

        int last_label_week = -3;
        
        for (int m = 1; m <= 12; m++) {
            var month_date = new GLib.DateTime.local (year, m, 1, 0, 0, 0);
            
            var diff = month_date.difference (start_date);
            int days_since_start = (int) (diff / TimeSpan.DAY);
            
            int week = (days_since_start + start_offset) / 7;
            
            if (week - last_label_week >= 3) {
                string month_name = month_date.format ("%b");
                
                double x = week * (cell_size + spacing);
                
                cr.move_to (x, 10);
                cr.show_text (month_name);
                
                last_label_week = week;
            }
        }

        for (int i = 0; i < 365; i++) {
            var current_date = start_date.add_days (i);
            string date_str = current_date.format ("%Y-%m-%d");

            int week = (i + start_offset) / 7;
            int day = (i + start_offset) % 7;

            double x = week * (cell_size + spacing);
            double y = start_y + (day * (cell_size + spacing));

            if (data.has_key (date_str)) {
                cr.set_source_rgb (0.88, 0.11, 0.14);
            } else {
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.15);
            }

            double radius = cell_size * 0.25;
            double degrees = Math.PI / 180.0;
            cr.new_sub_path ();
            cr.arc (x + cell_size - radius, y + radius, radius, -90 * degrees, 0 * degrees);
            cr.arc (x + cell_size - radius, y + cell_size - radius, radius, 0 * degrees, 90 * degrees);
            cr.arc (x + radius, y + cell_size - radius, radius, 90 * degrees, 180 * degrees);
            cr.arc (x + radius, y + radius, radius, 180 * degrees, 270 * degrees);
            cr.close_path ();
            cr.fill ();
        }
    }
}
