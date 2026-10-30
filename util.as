// Small text helpers the scripts share.

string Trim(const string &in text)
{
    int a = 0, b = int(text.length()) - 1;
    while (a <= b && (text[a] == 32 || text[a] == 9 || text[a] == 10 || text[a] == 13))
        a++;
    while (b >= a && (text[b] == 32 || text[b] == 9 || text[b] == 10 || text[b] == 13))
        b--;
    return text.substr(a, b - a + 1);
}

string Lower(const string &in text)
{
    string t = text;
    for (uint i = 0; i < t.length(); i++)
        if (t[i] >= 65 && t[i] <= 90)
            t[i] = t[i] + 32;
    return t;
}

string Replace(const string &in text, const string &in what, const string &in with)
{
    if (what == "")
        return text;
    string res;
    int at = 0;
    for (;;)
    {
        int found = text.findFirst(what, at);
        if (found < 0)
            break;
        res += text.substr(at, found - at) + with;
        at = found + int(what.length());
    }
    return res + text.substr(at);
}

string Join(const array<string>@ parts, const string &in between)
{
    string res;
    for (uint i = 0; i < parts.length(); i++)
        res += (i == 0 ? "" : between) + parts[i];
    return res;
}

// A link from a name, as the site makes a prefab's slug: lower case, every other run of characters a dash.
string Slug(const string &in name)
{
    string res, lower = Lower(name);
    bool dash = false;
    for (uint i = 0; i < lower.length() && res.length() < 48; i++)
    {
        uint8 c = lower[i];
        if ((c >= 97 && c <= 122) || (c >= 48 && c <= 57))
        {
            if (dash && res != "")
                res += "-";
            res += lower.substr(i, 1);
            dash = false;
        }
        else
            dash = true;
    }
    return res == "" ? "prefab" : res;
}

// The name the game saves a prefab's file under (the site's fileNameOf): letters, digits, _ and -, up to 64.
string FileName(const string &in name)
{
    string res, lower = Lower(Trim(name));
    for (uint i = 0; i < lower.length() && res.length() < 64; i++)
    {
        uint8 c = lower[i];
        bool ok = (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 45 || c == 95;
        if (ok)
            res += lower.substr(i, 1);
        else if (res != "" && res.substr(res.length() - 1) != "_")
            res += "_";
    }
    while (res.length() > 0 && res.substr(res.length() - 1) == "_")
        res = res.substr(0, res.length() - 1);
    return res == "" ? "prefab" : res;
}

double Round(double v) { return double(int64(v >= 0 ? v + 0.5 : v - 0.5)); }

string OneDecimal(double v) { return formatFloat(v, "", 0, 1); }

// "38 KB", "1.2 MB"
string FileSize(int bytes)
{
    if (bytes < 1024)
        return bytes + " B";
    if (bytes < 1024 * 1024)
        return (bytes + 512) / 1024 + " KB";
    return OneDecimal(bytes / (1024.0 * 1024.0)) + " MB";
}

// "0.2 × 12.0 × 4.0 m" from "w,d,h"
string SizeText(const string &in size)
{
    array<string>@ p = size.split(",");
    if (p.length() != 3)
        return "";
    return p[0] + " × " + p[1] + " × " + p[2] + " m";
}

string Shorten(const string &in text, uint most)
{
    return text.length() <= most ? text : text.substr(0, most - 1) + "…";
}

// "2026-10-16T10:00:00.000Z" as "Oct 16"; anything else as it is
string DateText(const string &in iso)
{
    if (iso.length() < 10 || iso.substr(4, 1) != "-")
        return iso;
    array<string> months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
    int m = parseInt(iso.substr(5, 2));
    return (m >= 1 && m <= 12 ? months[m - 1] : "?") + " " + parseInt(iso.substr(8, 2));
}
