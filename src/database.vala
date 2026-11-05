/* database.vala
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

public class Bloom.Database : GLib.Object {
    private static Bloom.Database? instance = null;

    private Sqlite.Database db;
    public string db_path { get; private set; }

    private const int CURRENT_DB_VERSION = 1;

    public static Bloom.Database get_instance () {
        if (instance == null) {
            instance = new Bloom.Database ();
        }
        return instance;
    }

    private Database () {
        var data_dir = GLib.Environment.get_user_data_dir ();
        var bloom_dir = Path.build_filename (data_dir, "bloom");
        DirUtils.create_with_parents (bloom_dir, 0700);

        this.db_path = Path.build_filename (bloom_dir, "bloom.db");

        if (Sqlite.Database.open (this.db_path, out db) != Sqlite.OK) {
            critical ("Can't open database: %s", db.errmsg ());
            return;
        }

        try {
            var file = File.new_for_path (this.db_path);
            file.set_attribute_uint32 (FileAttribute.UNIX_MODE, 384, FileQueryInfoFlags.NONE);
        } catch (Error e) {
            warning ("Could not set database permissions: %s", e.message);
        }

        string query = """
            CREATE TABLE IF NOT EXISTS day_logs (
                date TEXT PRIMARY KEY,
                is_period INTEGER DEFAULT 0,
                flow INTEGER DEFAULT 0,
                ovulation_test INTEGER DEFAULT 0,
                temperature REAL DEFAULT 0.0,
                cervical_mucus INTEGER DEFAULT 0,
                notes TEXT DEFAULT '',
                cramps INTEGER DEFAULT 0,
                bloating INTEGER DEFAULT 0,
                tenderness INTEGER DEFAULT 0,
                fatigue INTEGER DEFAULT 0,
                headache INTEGER DEFAULT 0,
                mood INTEGER DEFAULT 0,
                cravings INTEGER DEFAULT 0
            );
        """;
        db.exec (query, null, null);

        // int current_version = get_user_version ();

        // if (current_version < 2) {
            // db.exec ("ALTER TABLE day_logs ADD COLUMN temperature REAL DEFAULT 0.0;", null, null);

            // set_user_version (2);
            // message ("Database upgraded to version 2");
        // }
    }

    public void save_log (string date, string column, int value) {
        string query = @"INSERT INTO day_logs (date, $column) VALUES (?, ?)
                         ON CONFLICT(date) DO UPDATE SET $column = excluded.$column;";
        Sqlite.Statement stmt;

        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return;

        stmt.bind_text (1, date);
        stmt.bind_int (2, value);
        stmt.step ();
    }

    public int get_log (string date, string column) {
        string query = @"SELECT $column FROM day_logs WHERE date = ?;";
        Sqlite.Statement stmt;

        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return 0;

        stmt.bind_text (1, date);
        if (stmt.step () == Sqlite.ROW) {
            return stmt.column_int (0);
        }

        return 0;
    }

    public void save_temperature (string date, double value) {
        string query = "INSERT INTO day_logs (date, temperature) VALUES (?, ?)
                        ON CONFLICT(date) DO UPDATE SET temperature = excluded.temperature;";
        Sqlite.Statement stmt;
        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return;
        stmt.bind_text (1, date);
        stmt.bind_double (2, value);
        stmt.step ();
    }

    public double get_temperature (string date) {
        string query = "SELECT temperature FROM day_logs WHERE date = ?;";
        Sqlite.Statement stmt;
        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return 0.0;
        stmt.bind_text (1, date);
        if (stmt.step () == Sqlite.ROW) {
            return stmt.column_double (0);
        }
        return 0.0;
    }

    public void save_notes (string date, string value) {
        string query = "INSERT INTO day_logs (date, notes) VALUES (?, ?)
                        ON CONFLICT(date) DO UPDATE SET notes = excluded.notes;";
        Sqlite.Statement stmt;
        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return;
        stmt.bind_text (1, date);
        stmt.bind_text (2, value);
        stmt.step ();
    }

    public string get_notes (string date) {
        string query = "SELECT notes FROM day_logs WHERE date = ?;";
        Sqlite.Statement stmt;
        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return "";
        stmt.bind_text (1, date);
        if (stmt.step () == Sqlite.ROW) {
            return stmt.column_text (0);
        }
        return "";
    }

    public Gee.ArrayList<string> get_all_period_days () {
        var dates = new Gee.ArrayList<string> ();
        string query = "SELECT date FROM day_logs WHERE is_period = 1 ORDER BY date ASC;";
        Sqlite.Statement stmt;

        if (db.prepare_v2 (query, -1, out stmt) == Sqlite.OK) {
            while (stmt.step () == Sqlite.ROW) {
                dates.add (stmt.column_text (0));
            }
        }

        return dates;
    }

    public Gee.ArrayList<string> get_all_positive_opk_dates () {
        var dates = new Gee.ArrayList<string> ();
        string query = "SELECT date FROM day_logs WHERE ovulation_test >= 2 ORDER BY date ASC;";
        Sqlite.Statement stmt;

        if (db.prepare_v2 (query, -1, out stmt) == Sqlite.OK) {
            while (stmt.step () == Sqlite.ROW) {
                dates.add (stmt.column_text (0));
            }
        }
        return dates;
    }

    public void delete_all_data () {
        db.exec ("DELETE FROM day_logs;", null, null);
    }
    
    public void delete_day (string date) {
        string query = "DELETE FROM day_logs WHERE date = ?;";
        Sqlite.Statement stmt;

        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return;
        
        stmt.bind_text (1, date);
        stmt.step ();
    }
    
    public Gee.HashMap<string, string> search_notes (string search_term) {
        var results = new Gee.HashMap<string, string> ();
        string query;
        
        if (search_term == "") {
            query = "SELECT date, notes FROM day_logs WHERE notes != '' ORDER BY date DESC;";
        } else {
            query = "SELECT date, notes FROM day_logs WHERE notes LIKE ? ORDER BY date DESC;";
        }

        Sqlite.Statement stmt;
        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return results;

        if (search_term != "") {
            stmt.bind_text (1, "%" + search_term + "%");
        }

        while (stmt.step () == Sqlite.ROW) {
            results.set (stmt.column_text (0), stmt.column_text (1));
        }

        return results;
    }

    public void export_to_csv (string file_path) {
        string query = """
            SELECT * FROM day_logs 
            WHERE is_period = 1 
               OR flow > 0 
               OR cramps = 1 
               OR bloating = 1 
               OR tenderness = 1 
               OR fatigue = 1 
               OR headache = 1 
               OR mood = 1 
               OR cravings = 1 
               OR temperature > 0.0 
               OR notes != '' 
               OR cervical_mucus > 0 
               OR ovulation_test > 0
            ORDER BY date ASC;
        """;
        Sqlite.Statement stmt;

        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) return;

        try {
            var file = File.new_for_path (file_path);
            var stream = file.replace (null, false, FileCreateFlags.NONE, null);
            var data_stream = new DataOutputStream (stream);

            data_stream.put_string ("date,is_period,flow,cramps,bloating,tenderness,fatigue,headache,mood,cravings,temperature,notes,cervical_mucus,ovulation_test\n");

            while (stmt.step () == Sqlite.ROW) {
                string date = stmt.column_text (0);
                int is_period = stmt.column_int (1);
                int flow = stmt.column_int (2);
                int cramps = stmt.column_int (3);
                int bloating = stmt.column_int (4);
                int tenderness = stmt.column_int (5);
                int fatigue = stmt.column_int (6);
                int headache = stmt.column_int (7);
                int mood = stmt.column_int (8);
                int cravings = stmt.column_int (9);
                double temp = stmt.column_double (10);
                string notes = stmt.column_text (11);
                int cm = stmt.column_int (12);
                int opk = stmt.column_int (13);

                string escaped_notes = notes.replace ("\"", "\"\"");
                if (escaped_notes.contains (",") || escaped_notes.contains ("\n")) {
                    escaped_notes = "\"" + escaped_notes + "\"";
                }

                string line = @"$date,$is_period,$flow,$cramps,$bloating,$tenderness,$fatigue,$headache,$mood,$cravings,$temp,$escaped_notes,$cm,$opk\n";
                data_stream.put_string (line);
            }

            data_stream.close ();
        } catch (Error e) {
            critical ("Failed to export CSV: %s", e.message);
        }
    }
    
    public bool import_from_csv (string file_path, out string error_message) {
        error_message = "";
        Sqlite.Statement stmt;
        string query = """
            INSERT INTO day_logs (
                date, is_period, flow, cramps, bloating, tenderness, fatigue, headache, 
                mood, cravings, temperature, notes, cervical_mucus, ovulation_test
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET 
                is_period = excluded.is_period,
                flow = excluded.flow,
                cramps = excluded.cramps,
                bloating = excluded.bloating,
                tenderness = excluded.tenderness,
                fatigue = excluded.fatigue,
                headache = excluded.headache,
                mood = excluded.mood,
                cravings = excluded.cravings,
                temperature = excluded.temperature,
                notes = excluded.notes,
                cervical_mucus = excluded.cervical_mucus,
                ovulation_test = excluded.ovulation_test;
        """;

        if (db.prepare_v2 (query, -1, out stmt) != Sqlite.OK) {
            error_message = db.errmsg ();
            return false;
        }

        db.exec ("BEGIN TRANSACTION;", null, null);

        try {
            var file = File.new_for_path (file_path);
            uint8[] contents;
            file.load_contents (null, out contents, null);
            string full_text = (string) contents;

            var rows = new Gee.ArrayList<string> ();
            var buffer = new StringBuilder ();
            int depth = 0;

            for (int i = 0; i < full_text.length; i++) {
                char ch = full_text[i];
                
                if (ch == '"') depth = (depth == 1) ? 0 : 1;
                
                if (ch == '\n' && depth == 0) {
                    string row = buffer.str;
                    if (row.has_suffix ("\r")) row = row.substring (0, row.length - 1);
                    rows.add (row);
                    buffer = new StringBuilder ();
                } else {
                    buffer.append_c (ch);
                }
            }

            if (buffer.str.strip () != "") {
                string row = buffer.str;
                if (row.has_suffix ("\r")) row = row.substring (0, row.length - 1);
                rows.add (row);
            }

            bool is_header = true;
            foreach (var row in rows) {
                if (is_header) {
                    is_header = false;
                    continue;
                }
                if (row.strip () == "") continue;

                string[] parts = parse_csv_line (row);
                
                if (parts.length < 14) {
                    var padded = new Gee.ArrayList<string> ();
                    foreach (var p in parts) padded.add (p);
                    while (padded.size < 14) padded.add ("");
                    parts = padded.to_array ();
                }

                stmt.reset ();
                
                stmt.bind_text (1, parts[0].strip ());
                stmt.bind_int (2, safe_parse_int (parts[1]));
                stmt.bind_int (3, safe_parse_int (parts[2]));
                stmt.bind_int (4, safe_parse_int (parts[3]));
                stmt.bind_int (5, safe_parse_int (parts[4]));
                stmt.bind_int (6, safe_parse_int (parts[5]));
                stmt.bind_int (7, safe_parse_int (parts[6]));
                stmt.bind_int (8, safe_parse_int (parts[7]));
                stmt.bind_int (9, safe_parse_int (parts[8]));
                stmt.bind_int (10, safe_parse_int (parts[9]));
                stmt.bind_double (11, safe_parse_double (parts[10]));
                stmt.bind_text (12, parts[11]);
                stmt.bind_int (13, safe_parse_int (parts[12]));
                stmt.bind_int (14, safe_parse_int (parts[13]));

                if (stmt.step () != Sqlite.DONE) {
                    error_message = db.errmsg ();
                    db.exec ("ROLLBACK;", null, null);
                    return false;
                }
            }
            
            db.exec ("COMMIT;", null, null);
            return true;

        } catch (Error e) {
            error_message = e.message;
            db.exec ("ROLLBACK;", null, null);
            return false;
        }
    }

    private string[] parse_csv_line (string line) {
        var result = new Gee.ArrayList<string> ();
        var current = new StringBuilder ();
        bool in_quotes = false;

        for (int i = 0; i < line.length; i++) {
            char c = line[i];

            if (in_quotes) {
                if (c == '"') {
                    if (i + 1 < line.length && line[i + 1] == '"') {
                        current.append_c ('"');
                        i++;
                    } else {
                        in_quotes = false;
                    }
                } else {
                    current.append_c (c);
                }
            } else {
                if (c == '"') {
                    in_quotes = true;
                } else if (c == ',') {
                    result.add (current.str);
                    current = new StringBuilder ();
                } else {
                    current.append_c (c);
                }
            }
        }
        result.add (current.str);
        return result.to_array ();
    }
    
    private int safe_parse_int (string s) {
        if (s == null || s.strip () == "") return 0;
        return int.parse (s);
    }
    
    private double safe_parse_double (string s) {
        if (s == null || s.strip () == "") return 0.0;
        return double.parse (s);
    }

    private int get_user_version () {
        Sqlite.Statement stmt;
        if (db.prepare_v2 ("PRAGMA user_version;", -1, out stmt) == Sqlite.OK) {
            if (stmt.step () == Sqlite.ROW) {
                return stmt.column_int (0);
            }
        }
        return 0;
    }

    private void set_user_version (int version) {
        string query = @"PRAGMA user_version = $version;";
        db.exec (query, null, null);
    }
    
    public Gee.HashMap<string, bool> get_year_period_days (int year) {
        var data = new Gee.HashMap<string, bool> ();
        string query = @"SELECT date FROM day_logs WHERE is_period = 1 AND date LIKE '$year-%';";
        Sqlite.Statement stmt;

        if (db.prepare_v2 (query, -1, out stmt) == Sqlite.OK) {
            while (stmt.step () == Sqlite.ROW) {
                data.set (stmt.column_text (0), true);
            }
        }
        return data;
    }

    public Gee.ArrayList<int> get_years_with_data () {
        var years = new Gee.ArrayList<int> ();
        string query = "SELECT DISTINCT substr(date, 1, 4) FROM day_logs ORDER BY date DESC;";
        Sqlite.Statement stmt;

        if (db.prepare_v2 (query, -1, out stmt) == Sqlite.OK) {
            while (stmt.step () == Sqlite.ROW) {
                years.add (int.parse (stmt.column_text (0)));
            }
        }
        // Always include the current year
        int current_year = new GLib.DateTime.now_local ().get_year ();
        if (!years.contains (current_year)) {
            years.add (current_year);
        }
        return years;
    }
}
