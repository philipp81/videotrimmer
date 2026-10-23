// TimeUtil.hpp — reine C++-Hilfsfunktionen zum Formatieren und Parsen von Zeitangaben.
#pragma once

#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <string>
#include <vector>

namespace vt {

// "m:ss.cc" bzw. "h:mm:ss.cc", sobald Stunden vorkommen (oder forceHours gesetzt ist).
inline std::string formatTime(double seconds, bool forceHours = false)
{
    if (std::isnan(seconds) || seconds < 0) seconds = 0;
    long long cs = std::llround(seconds * 100.0);
    long long h = cs / 360000; cs -= h * 360000;
    long long m = cs / 6000;   cs -= m * 6000;
    long long s = cs / 100;    cs -= s * 100;
    char buf[48];
    if (h > 0 || forceHours)
        std::snprintf(buf, sizeof buf, "%lld:%02lld:%02lld.%02lld", h, m, s, cs);
    else
        std::snprintf(buf, sizeof buf, "%lld:%02lld.%02lld", m, s, cs);
    return buf;
}

// Kompakte Form für Dateinamen, z. B. "02m03s" oder "1h02m03s".
inline std::string formatTimeForFilename(double seconds)
{
    if (std::isnan(seconds) || seconds < 0) seconds = 0;
    long long t = std::llround(seconds);
    long long h = t / 3600, m = (t % 3600) / 60, s = t % 60;
    char buf[48];
    if (h > 0) std::snprintf(buf, sizeof buf, "%lldh%02lldm%02llds", h, m, s);
    else       std::snprintf(buf, sizeof buf, "%02lldm%02llds", m, s);
    return buf;
}

// Akzeptiert "ss", "ss.cc", "m:ss", "h:mm:ss", Bruchteile mit '.' oder ','.
// Leerzeichen werden ignoriert. Ungültige Eingaben liefern std::nullopt.
inline std::optional<double> parseTime(const std::string& input)
{
    std::string s;
    for (char c : input) {
        if (c == ' ' || c == '\t') continue;
        s.push_back(c == ',' ? '.' : c);
    }
    if (s.empty()) return std::nullopt;

    std::vector<std::string> parts;
    size_t pos = 0;
    for (;;) {
        size_t colon = s.find(':', pos);
        parts.push_back(colon == std::string::npos ? s.substr(pos) : s.substr(pos, colon - pos));
        if (colon == std::string::npos) break;
        pos = colon + 1;
    }
    if (parts.size() > 3) return std::nullopt;

    double total = 0;
    for (size_t i = 0; i < parts.size(); ++i) {
        const std::string& p = parts[i];
        const bool last = (i + 1 == parts.size());
        bool sawDigit = false, sawDot = false;
        for (char c : p) {
            if (std::isdigit(static_cast<unsigned char>(c))) { sawDigit = true; continue; }
            if (last && c == '.' && !sawDot) { sawDot = true; continue; }
            return std::nullopt;
        }
        if (!sawDigit) return std::nullopt;
        total = total * 60.0 + std::strtod(p.c_str(), nullptr);
    }
    return total;
}

} // namespace vt
