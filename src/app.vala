/* app.vala
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

public class Bloom.Application : Adw.Application {
    private GLib.Settings settings;

    public Application () {
        Object (
            application_id: "io.github.oatbiscuit.bloom",
            flags: ApplicationFlags.DEFAULT_FLAGS,
            resource_base_path: "/io/github/oatbiscuit/bloom"
        );
    }

    construct {
        this.settings = new GLib.Settings ("io.github.oatbiscuit.bloom");

        ActionEntry[] action_entries = {
            { "about", this.on_about_action },
            { "preferences", this.on_preferences_action },
            { "quit", this.quit },
        };
        this.add_action_entries (action_entries, this);
        this.set_accels_for_action ("app.quit", { "<primary>q" });
        
        GLib.Timeout.add_seconds (3600, () => {
            check_period_reminder ();
            return true;
        });
    }

    public override void activate () {
        base.activate ();
        var provider = new Gtk.CssProvider ();
        provider.load_from_resource ("/io/github/oatbiscuit/bloom/css/style.css");

        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
        var win = this.active_window ?? new Bloom.Window (this);
        
        check_period_reminder ();
        
        win.present ();
    }

    private void on_about_action () {
        string[] developers = { "oatbiscuit" };
        var about = new Adw.AboutDialog () {
            application_name = _("Bloom"),
            comments = _("Track your menstrual cycle and symptoms"),
            website = "https://github.com/oatbiscuit/bloom",
            issue_url = "https://github.com/oatbiscuit/bloom/issues/new",
			license_type = Gtk.License.GPL_3_0,
            application_icon = "io.github.oatbiscuit.bloom",
            developer_name = "oatbiscuit",
            translator_credits = _("translator-credits"),
            version = "1.0.0",
            developers = developers,
            copyright = "© 2026 oatbiscuit",
        };

        about.add_legal_section (
            _("Medical Disclaimer"),
            _("Bloom is a wellness tracker intended for personal awareness only. It is not a medical application and should not be used as a method of contraception or for medical diagnosis. The predictions provided are estimates based on historical data and should not replace professional medical advice."),
            Gtk.License.CUSTOM,
            null
        );

        about.present (this.active_window);
    }

    private void on_preferences_action () {
        var prefs = new Bloom.PreferencesDialog ();

        var main_window = this.active_window as Bloom.Window;
        if (main_window != null) {
            prefs.on_close_callback = main_window.rebuild_grid;
        }

        prefs.present (this.active_window);
    }
    
    public void send_bloom_notification (string id, string title, string body, string icon_name = "dialog-information") {
        var notification = new GLib.Notification (title);
        notification.set_body (body);
        notification.set_icon (new GLib.ThemedIcon (icon_name));
        this.send_notification (id, notification);
    }
    
    private void check_period_reminder () {
        var engine = new Bloom.CycleEngine ();
        var next_period = engine.get_next_period_date ();
        
        if (next_period == null) return;

        var today = new GLib.DateTime.now_local ();

        var today_midnight = new GLib.DateTime.local (
            today.get_year (), today.get_month (), today.get_day_of_month (), 0, 0, 0
        );
        var period_midnight = new GLib.DateTime.local (
            next_period.get_year (), next_period.get_month (), next_period.get_day_of_month (), 0, 0, 0
        );

        var diff = period_midnight.difference (today_midnight);
        int days_until = (int) (diff / TimeSpan.DAY);

        if (days_until != 2 && days_until != 1 && days_until != 0) {
            return;
        }

        string today_str = today.format ("%Y-%m-%d");
        string last_sent = settings.get_string ("last-period-reminder");

        if (last_sent == today_str) {
            return;
        }

        string title = "";
        string body = "";

        if (days_until == 2) {
            title = _("Period Approaching");
            body = _("Your period is due in 2 days.");
        } else if (days_until == 1) {
            title = _("Period Approaching");
            body = _("Your period is due tomorrow.");
        } else if (days_until == 0) {
            title = _("Period Expected Today");
            body = _("Your period is predicted to start today.");
        }

        this.send_bloom_notification (
            "period-reminder",
            title,
            body,
            "x-office-calendar-symbolic"
        );

        settings.set_string ("last-period-reminder", today_str);
    }
}
