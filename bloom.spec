%global appid io.github.oatbiscuit.bloom
%{!?version:%global version 1.0.0}

Name:		bloom
Version:	%{version}
Release:	1%{?dist}
Summary:	Private and native cycle tracker for GNOME

License:	GPL-3.0-or-later
URL:		https://github.com/oatbiscuit/bloom
Source0:	bloom-%{version}.tar.xz

BuildRequires:  meson
BuildRequires:  vala
BuildRequires:  pkgconfig(gtk4)
BuildRequires:  pkgconfig(libadwaita-1)
BuildRequires:  pkgconfig(sqlite3)
BuildRequires:  pkgconfig(gee-0.8)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  blueprint-compiler
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib

%description
Bloom is a private, and native cycle tracker for GNOME.
It helps you understand your body's patterns by predicting upcoming
periods and ovulation days without ever sending your data to the cloud.

%prep
%autosetup -n bloom-%{version}

%build
%meson
%meson_build

%install
%meson_install

%files
%{_bindir}/%{name}
%{_datadir}/applications/%{appid}.desktop
%{_datadir}/metainfo/%{appid}.metainfo.xml
%{_datadir}/icons/hicolor/scalable/apps/%{appid}.svg
%{_datadir}/icons/hicolor/symbolic/apps/%{appid}-symbolic.svg
%{_datadir}/glib-2.0/schemas/%{appid}.gschema.xml
%{_datadir}/dbus-1/services/%{appid}.service
%{_datadir}/locale/*/LC_MESSAGES/%{appid}.mo

%changelog
* Thu Nov 12 2026 oatbiscuit <kingorgg@gmail.com> - 1.0.0-1
- Initial package for Bloom