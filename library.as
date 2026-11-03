// The prefabs on this PC: each one a file in the game's Prefabs folder (Prefabs::Folder), and what this plugin knows
// of it, kept in its storage: where it came from (made here and only here, made here and published, or downloaded),
// its store slug, and the store's details. The folder is the truth: a file made with the game's own console is added
// as a local one, and a record whose file is gone is dropped. Old versions kept by "replace with the selection" are
// files named "<file>--v<n>", hidden from the lists.

namespace Library
{

const string LOCAL = "local", MINE = "mine", DOWNLOADED = "downloaded";

class Rec
{
    string file;                // its file's name in the Prefabs folder, without .json
    string name, description, tags;
    string source = LOCAL;
    string slug;                // on the store ("" when it isn't)
    string uploaderId, uploaderName;
    string remoteUpdated;       // the store's updatedAt when it was downloaded or last published
    string publishedHash;       // the file's hash then: a different one now is a change not yet published
    string thumb;               // a picture of it, a file ("" for none)
    string size;                // "w,d,h" in metres
    int pieces = 0, bytes = 0, favorites = 0, versions = 0;
    bool goneFromStore = false; // deleted or taken down on the store since
    string storeUpdated;        // the store's updatedAt now, when it is newer than ours
}

array<Rec@> recs;
const string FIELDS_SEP = "\t";

void Load()
{
    recs.resize(0);
    array<string>@ files = Storage::Get("lib.files", "").split("|");
    for (uint i = 0; i < files.length(); i++)
    {
        if (files[i] == "")
            continue;
        array<string>@ f = Storage::Get("lib.r." + files[i], "").split(FIELDS_SEP);
        if (f.length() < 18)
            continue;
        Rec r;
        r.file = files[i];
        r.name = f[0];
        r.description = f[1];
        r.tags = f[2];
        r.source = f[3];
        r.slug = f[4];
        r.uploaderId = f[5];
        r.uploaderName = f[6];
        r.remoteUpdated = f[7];
        r.publishedHash = f[8];
        r.thumb = f[9];
        r.size = f[10];
        r.pieces = parseInt(f[11]);
        r.bytes = parseInt(f[12]);
        r.favorites = parseInt(f[13]);
        r.versions = parseInt(f[14]);
        r.goneFromStore = f[15] == "1";
        r.storeUpdated = f[16];
        recs.insertLast(r);
    }
    Reconcile();
}

void Save(Rec@ r)
{
    array<string> f = {Line(r.name), Line(r.description), r.tags, r.source, r.slug, r.uploaderId, Line(r.uploaderName),
                       r.remoteUpdated, r.publishedHash, r.thumb, r.size, "" + r.pieces, "" + r.bytes, "" + r.favorites,
                       "" + r.versions, r.goneFromStore ? "1" : "0", r.storeUpdated, "end"};
    Storage::Set("lib.r." + r.file, Join(f, FIELDS_SEP));
    SaveList();
}

void SaveList()
{
    array<string> files;
    for (uint i = 0; i < recs.length(); i++)
        files.insertLast(recs[i].file);
    Storage::Set("lib.files", Join(files, "|"));
}

string Line(const string &in s) { return Replace(Replace(s, "\t", " "), "\n", " "); }

bool IsBackup(const string &in file) { return file.findFirst("--v") >= 0; }

// The folder against the records: new files are local prefabs, records without a file go.
void Reconcile()
{
    array<string>@ files = Prefabs::List();
    for (int i = int(recs.length()) - 1; i >= 0; i--)
        if (files.find(recs[i].file) < 0)
        {
            Storage::Set("lib.r." + recs[i].file, "");
            recs.removeAt(uint(i));
        }
    for (uint i = 0; i < files.length(); i++)
    {
        if (IsBackup(files[i]) || Find(files[i]) !is null)
            continue;
        Rec r;
        r.file = files[i];
        r.name = files[i];
        r.pieces = -1;                  // measured a few at a time over the next frames (MeasureSome)
        recs.insertLast(r);
        Save(r);
    }
    SaveList();
}

// Prefabs not measured yet (a first start, or files the game saved), measured while this frame has time: reading and
// parsing a big prefab takes a few ms, and a call that runs past the host's budget stops the plugin.
void MeasureSome()
{
    double until = Host::Time() + 0.012;
    for (uint i = 0; i < recs.length(); i++)
    {
        if (recs[i].pieces >= 0)
            continue;
        Measure(recs[i]);
        Save(recs[i]);
        Jobs::changes++;
        if (Host::Time() >= until)
            return;
    }
}

Rec@ Find(const string &in file)
{
    for (uint i = 0; i < recs.length(); i++)
        if (recs[i].file == file)
            return recs[i];
    return null;
}

Rec@ BySlug(const string &in slug)
{
    for (uint i = 0; i < recs.length(); i++)
        if (recs[i].slug == slug && slug != "")
            return recs[i];
    return null;
}

// The store's picture of `slug` arrived: the prefab here with that slug shows it too.
void NoteThumb(const string &in slug, const string &in path)
{
    Rec@ r = BySlug(slug);
    if (r is null || r.thumb == path)
        return;
    r.thumb = path;
    Save(r);
    Jobs::changes++;
}

// pieces, size and bytes from its file
void Measure(Rec@ r)
{
    string text = Prefabs::Read(r.file);
    r.pieces = Json::Count(text, "items");
    r.bytes = int(text.length());
    r.size = SizeOfFile(text);
}

bool Mine(Rec@ r)
{
    return r.source == MINE || (r.source == DOWNLOADED && r.uploaderId != "" && r.uploaderId == Steam::OwnId());
}

// Changed here since it was published (its file isn't what the store has).
bool ChangedHere(Rec@ r)
{
    return r.slug != "" && Mine(r) && r.publishedHash != "" && Hash(Prefabs::Read(r.file)) != r.publishedHash;
}

// Whether a new version of it can go to the store: changed here, and the store takes new files (the practice copy does;
// ballestrecords.com keeps a prefab's file as it was uploaded).
bool CanPublishVersion(Rec@ r) { return ChangedHere(r) && Server::Fake(); }

// A file name for `name` that no prefab here has yet.
string FreeFile(const string &in name)
{
    string base = FileName(name), file = base;
    array<string>@ files = Prefabs::List();
    for (int n = 2; files.find(file) >= 0; n++)
        file = base + "_" + n;
    return file;
}

// FNV-1a of a file's text (line ends ignored), as hex: whether it is the version published.
string Hash(const string &in text)
{
    uint h = 2166136261;
    for (uint i = 0; i < text.length(); i++)
    {
        uint8 c = text[i];
        if (c == 13)
            continue;
        h ^= c;
        h *= 16777619;
    }
    return formatUInt(h, "H", 8);
}

// About how big a prefab is, from where its pieces are (the middle of each; the site measures their shapes too), in
// metres as "w,d,h". Reads up to 256 of its pieces.
string SizeOfFile(const string &in text)
{
    int n = Json::Count(text, "items");
    if (n <= 0)
        return "";
    int step = n > 256 ? n / 256 : 1;
    double lo0 = 1e18, lo1 = 1e18, lo2 = 1e18, hi0 = -1e18, hi1 = -1e18, hi2 = -1e18;
    for (int i = 0; i < n; i += step)
    {
        string at = "items." + i + ".transform.location.";
        double x = Json::Number(text, at + "0"), y = Json::Number(text, at + "1"), z = Json::Number(text, at + "2");
        lo0 = Min(lo0, x); hi0 = Max(hi0, x);
        lo1 = Min(lo1, y); hi1 = Max(hi1, y);
        lo2 = Min(lo2, z); hi2 = Max(hi2, z);
    }
    return OneDecimal((hi0 - lo0) / 100) + "," + OneDecimal((hi1 - lo1) / 100) + "," + OneDecimal((hi2 - lo2) / 100);
}

double Min(double a, double b) { return a < b ? a : b; }
double Max(double a, double b) { return a > b ? a : b; }

// --- changes --------------------------------------------------------------------------------------------------------

// The selection saved as a new local prefab. "" when saved, else why not (the game's reply).
string Create(const string &in name, const string &in description, const array<string>@ tags, Rec@ &out made)
{
    string file = FreeFile(name), reply;
    if (!Prefabs::Save(file, false, reply))
        return reply;
    Rec r;
    r.file = file;
    r.name = Trim(name);
    r.description = Trim(description);
    r.tags = Join(tags, ",");
    Measure(r);
    recs.insertLast(r);
    Save(r);
    @made = r;
    return "";
}

// The selection saved over `r`, its old file kept as the next "--v<n>" version. "" when done, else why not.
string ReplaceWithSelection(Rec@ r)
{
    string old = Prefabs::Read(r.file), reply;
    if (old == "")
        return "its file can't be read";
    string kept = Prefabs::Write(r.file + "--v" + (r.versions + 1), old);
    if (kept != "")
        return "couldn't keep the old version: " + kept;
    if (!Prefabs::Save(r.file, true, reply))
        return reply;
    r.versions++;
    Measure(r);
    Save(r);
    return "";
}

// Version `v` (1 to versions) put back, the file now kept as a version too.
string PutBack(Rec@ r, int v)
{
    string back = Prefabs::Read(r.file + "--v" + v), now = Prefabs::Read(r.file);
    if (back == "")
        return "that version is gone";
    string kept = Prefabs::Write(r.file + "--v" + (r.versions + 1), now);
    if (kept != "")
        return kept;
    string put = Prefabs::Write(r.file, back);
    if (put != "")
        return put;
    r.versions++;
    Measure(r);
    Save(r);
    return "";
}

// A downloaded file kept under its slug (or the slug and a number, when a prefab here has that name).
string KeepDownload(const string &in slug, const string &in text, Rec@ &out made)
{
    Rec@ r = BySlug(slug);
    string file = r !is null ? r.file : (Prefabs::List().find(slug) < 0 ? slug : FreeFile(slug));
    string written = Prefabs::Write(file, text);
    if (written != "")
        return written;
    if (r is null)
    {
        Rec fresh;
        @r = fresh;
        r.file = file;
        recs.insertLast(r);
    }
    r.publishedHash = Hash(text);
    r.storeUpdated = "";
    r.goneFromStore = false;
    Measure(r);
    @made = r;
    return "";
}

// Deleted from this PC: its file, its kept versions and its record.
string Forget(Rec@ r)
{
    string reply;
    if (!Prefabs::Delete(r.file, reply))
        return reply;
    for (int v = 1; v <= r.versions; v++)
        Prefabs::Delete(r.file + "--v" + v, reply);
    Storage::Set("lib.r." + r.file, "");
    recs.removeAt(uint(recs.findByRef(r)));
    SaveList();
    return "";
}

}  // namespace Library
