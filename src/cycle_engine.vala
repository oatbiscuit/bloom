/* cycle_engine.vala
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

public class Bloom.CycleEngine : GLib.Object {
    private Bloom.Database db;
    private GLib.Settings settings;

    private const int DEFAULT_CYCLE_LENGTH = 28;
    private const int DEFAULT_PERIOD_LENGTH = 5;
    private const int LUTEAL_PHASE_LENGTH = 14;

    public CycleEngine () {
        this.db = Bloom.Database.get_instance ();
        this.settings = new GLib.Settings ("io.github.oatbiscuit.bloom");
    }

    public Gee.ArrayList<GLib.DateTime> get_cycle_start_dates () {
        var starts = new Gee.ArrayList<GLib.DateTime> ();
        var all_days = db.get_all_period_days ();

        if (all_days.size == 0) {
            return starts;
        }

        var current_start = new GLib.DateTime.from_iso8601 (all_days[0] + "T00:00:00Z", null);
        starts.add (current_start);

        for (int i = 1; i < all_days.size; i++) {
            var day = new GLib.DateTime.from_iso8601 (all_days[i] + "T00:00:00Z", null);
            var previous_day = new GLib.DateTime.from_iso8601 (all_days[i-1] + "T00:00:00Z", null);

            if (day.difference (previous_day) > TimeSpan.DAY) {
                starts.add (day);
            }
        }

        return starts;
    }

    private Gee.ArrayList<int> get_period_lengths () {
        var lengths = new Gee.ArrayList<int> ();
        var all_days = db.get_all_period_days ();

        if (all_days.size == 0) {
            return lengths;
        }

        int current_block_length = 1;

        for (int i = 1; i < all_days.size; i++) {
            var day = new GLib.DateTime.from_iso8601 (all_days[i] + "T00:00:00Z", null);
            var previous_day = new GLib.DateTime.from_iso8601 (all_days[i - 1] + "T00:00:00Z", null);

            var diff = day.difference (previous_day);
            int days_diff = (int) (diff / TimeSpan.DAY);

            if (days_diff == 1) {
                current_block_length++;
            } else {
                lengths.add (current_block_length);
                current_block_length = 1;
            }
        }

        lengths.add (current_block_length);
        return lengths;
    }

    private int calculate_median (Gee.ArrayList<int> values) {
        if (values.size == 0) {
            return DEFAULT_CYCLE_LENGTH;
        }

        values.sort ((a, b) => a - b);
        int mid = values.size / 2;

        if (values.size % 2 == 0) {
            return (values[mid - 1] + values[mid]) / 2;
        } else {
            return values[mid];
        }
    }

    private int calculate_average (Gee.ArrayList<int> values) {
        if (values.size == 0) {
            return DEFAULT_CYCLE_LENGTH;
        }

        int sum = 0;
        foreach (int val in values) {
            sum += val;
        }

        return sum / values.size;
    }

    public Gee.ArrayList<int> get_rolling_window () {
        var starts = get_cycle_start_dates ();
        var lengths = new Gee.ArrayList<int> ();

        if (starts.size < 2) {
            return lengths;
        }

        for (int i = 1; i < starts.size; i++) {
            var diff = starts[i].difference (starts[i - 1]);
            int days = (int) (diff / TimeSpan.DAY);

            if (days >= 15 && days <= 60) {
                lengths.add (days);
            }
        }

        var window = new Gee.ArrayList<int> ();
        int start_index = int.max (0, lengths.size - 6);

        for (int i = start_index; i < lengths.size; i++) {
            window.add (lengths[i]);
        }

        return window;
    }

    public int get_median_cycle_length () {
        int custom_length = settings.get_int ("custom-cycle-length");
        if (custom_length > 0) {
            return custom_length;
        }

        var window = get_rolling_window ();

        if (window.size == 0) {
            return DEFAULT_CYCLE_LENGTH;
        }

        return calculate_median (window);
    }

    public int get_average_cycle_length () {
        var window = get_rolling_window ();

        if (window.size == 0) {
            return DEFAULT_CYCLE_LENGTH;
        }

        return calculate_average (window);
    }

    public int get_median_period_length () {
        int custom_length = settings.get_int ("custom-period-length");
        if (custom_length > 0) {
            return custom_length;
        }

        var lengths = get_period_lengths ();

        if (lengths.size == 0) {
            return DEFAULT_PERIOD_LENGTH;
        }

        return calculate_median (lengths);
    }

    public int get_average_period_length () {
        var lengths = get_period_lengths ();

        if (lengths.size == 0) {
            return DEFAULT_PERIOD_LENGTH;
        }

        return calculate_average (lengths);
    }

    public int get_luteal_phase_length () {
        return settings.get_int ("custom-luteal-phase");
    }

    public Gee.ArrayList<string> get_predicted_periods (GLib.DateTime current_month) {
        var predictions = new Gee.ArrayList<string> ();
        var starts = get_cycle_start_dates ();

        if (starts.size == 0) {
            return predictions;
        }

        var last_start = starts.last ();
        int median_cycle = get_median_cycle_length ();
        int median_period = get_median_period_length ();

        var next_period_start = last_start.add_days (median_cycle);

        for (int i = 0; i < median_period; i++) {
            predictions.add (next_period_start.add_days (i).format ("%Y-%m-%d"));
        }

        return predictions;
    }

    public Gee.ArrayList<string> get_predicted_ovulation (GLib.DateTime current_month) {
        var predictions = new Gee.ArrayList<string> ();
        var starts = get_cycle_start_dates ();
        int luteal_phase = get_luteal_phase_length ();

        var opk_dates = db.get_all_positive_opk_dates ();
        var opk_ovulation_dates = new Gee.ArrayList<string> ();

        foreach (var opk_date_string in opk_dates) {
            var opk_date = new GLib.DateTime.from_iso8601 (opk_date_string + "T00:00:00Z", null);
            var ov_date = opk_date.add_days (1);

            opk_ovulation_dates.add (ov_date.format ("%Y-%m-%d"));
        }

        for (int i = 0; i < starts.size; i++) {
            if (i < starts.size - 1) {
                var next_period = starts[i + 1];
                var estimated_ovulation = next_period.add_days (-luteal_phase);

                string date_string = estimated_ovulation.format ("%Y-%m-%d");

                if (!opk_ovulation_dates.contains (date_string)) {
                    predictions.add (date_string);
                }
            }
        }

        foreach (var opk_date in opk_ovulation_dates) {
            predictions.add (opk_date);
        }

        if (starts.size > 0) {
            var last_start = starts.last ();
            int median_cycle = get_median_cycle_length ();
            var next_period_start = last_start.add_days (median_cycle);
            var ovulation_date = next_period_start.add_days (-luteal_phase);

            string date_string = ovulation_date.format ("%Y-%m-%d");

            if (!opk_ovulation_dates.contains (date_string)) {
                predictions.add (date_string);
            }
        }
        return predictions;
    }

    public GLib.DateTime? get_next_period_date () {
        var starts = get_cycle_start_dates ();
        if (starts.size == 0) return null;

        var last_start = starts.last ();
        int median_cycle = get_median_cycle_length ();

        return last_start.add_days (median_cycle);
    }

    public int get_current_cycle_day (GLib.DateTime target_date) {
        var starts = get_cycle_start_dates ();
        if (starts.size == 0) return 0;

        GLib.DateTime? closest_start = null;

        for (int i = starts.size - 1; i >= 0; i--) {
            if (starts[i].compare (target_date) <= 0) {
                closest_start = starts[i];
                break;
            }
        }

        if (closest_start == null) return 0;

        var d1 = new GLib.DateTime.local (
            closest_start.get_year (),
            closest_start.get_month (),
            closest_start.get_day_of_month (),
            0, 0, 0
        );
        var d2 = new GLib.DateTime.local (
            target_date.get_year (),
            target_date.get_month (),
            target_date.get_day_of_month (),
            0, 0, 0
        );

        var diff = d2.difference (d1);
        int days = (int) (diff / TimeSpan.DAY);

        return days + 1;
    }

    public int get_all_time_average_cycle_length () {
        var starts = get_cycle_start_dates ();
        var lengths = new Gee.ArrayList<int> ();

        if (starts.size < 2) return DEFAULT_CYCLE_LENGTH;

        for (int i = 1; i < starts.size; i++) {
            var diff = starts[i].difference (starts[i - 1]);
            int days = (int) (diff / TimeSpan.DAY);
            if (days >= 15 && days <= 60) {
                lengths.add (days);
            }
        }

        if (lengths.size == 0) return DEFAULT_CYCLE_LENGTH;
        return calculate_average (lengths);
    }

    public int get_all_time_average_period_length () {
        var lengths = get_period_lengths ();
        if (lengths.size == 0) return DEFAULT_PERIOD_LENGTH;
        return calculate_average (lengths);
    }

    public string get_regularity_label () {
        var window = get_rolling_window ();
        if (window.size < 2) return _("Not enough data");

        window.sort ((a, b) => a - b);
        int min = window[0];
        int max = window[window.size - 1];
        int variance = max - min;

        if (variance <= 4) {
            return _("Very Regular");
        } else if (variance <= 7) {
            return _("Regular");
        } else {
            return _("Irregular");
        }
    }
}
