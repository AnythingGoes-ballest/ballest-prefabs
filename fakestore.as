// The practice copy of the store (Server, while the site's routes for the game aren't live): the prefabs in
// data/store (made by the site's own Generators, their pictures drawn by its renderer), plus what the player uploads,
// kept in this plugin's storage so it survives a restart. It keeps the site's rules: only a prefab's uploader may change
// or delete it, 5 uploads and 60 hearts and edits an hour (counted this session: plugins have no clock).

namespace FakeStore
{

class Entry
{
    string slug, name, description, tags, uploaderId, uploaderName, created, updated;
    int pieces = 0, bytes = 0, seedHearts = 0;
    string size;                // "w,d,h" in metres
    bool seeded = false;
}

array<Entry@> entries;
bool loaded = false;
array<double> uploadTimes, writeTimes;      // when (Host::Time) each upload, and each heart or edit, was made
const string NEWLINE = "\x1e";  // a file's line ends, in a storage value (one line each)

void Load()
{
    if (loaded)
        return;
    loaded = true;
    array<string>@ lines = Plugins::ReadFile("data/store.txt").split("\n");
    array<string>@ removed = Storage::Get("fake.removed", "").split("|");
    for (uint i = 0; i < lines.length(); i++)
    {
        if (lines[i] == "" || lines[i].substr(0, 1) == "#")
            continue;
        array<string>@ f = lines[i].split("\t");
        if (f.length() < 13 || removed.find(f[0]) >= 0)
            continue;
        Entry e;
        e.seeded = true;
        e.slug = f[0];
        e.name = f[1];
        e.uploaderId = f[2];
        e.uploaderName = f[3];
        e.created = f[4];
        e.updated = Storage::Get("fake.updated." + e.slug, f[4]);
        e.seedHearts = parseInt(f[5]);
        e.tags = f[6];
        e.pieces = parseInt(f[7]);
        e.bytes = parseInt(f[8]);
        e.size = f[9] + "," + f[10] + "," + f[11];
        e.description = f[12];
        entries.insertLast(e);
    }
    array<string>@ added = Storage::Get("fake.added", "").split("|");
    for (uint i = 0; i < added.length(); i++)
    {
        array<string>@ f = Storage::Get("fake.e." + added[i], "").split("\t");
        if (added[i] == "" || f.length() < 10)
            continue;
        Entry e;
        e.slug = added[i];
        e.name = f[0];
        e.description = f[1];
        e.tags = f[2];
        e.uploaderId = f[3];
        e.uploaderName = f[4];
        e.created = f[5];
        e.updated = f[6];
        e.pieces = parseInt(f[7]);
        e.bytes = parseInt(f[8]);
        e.size = f[9];
        entries.insertLast(e);
    }
}

Entry@ Find(const string &in slug)
{
    Load();
    for (uint i = 0; i < entries.length(); i++)
        if (entries[i].slug == slug)
            return entries[i];
    return null;
}

bool Live(const string &in slug) { return Find(slug) !is null; }

void SaveEntry(Entry@ e)
{
    array<string> f = {OneLine(e.name), OneLine(e.description), e.tags, e.uploaderId, OneLine(e.uploaderName), e.created,
                       e.updated, "" + e.pieces, "" + e.bytes, e.size};
    Storage::Set("fake.e." + e.slug, Join(f, "\t"));
}

string OneLine(const string &in s) { return Replace(Replace(s, "\t", " "), "\n", " "); }

// --- what the server answers ------------------------------------------------------------------------------------------

int Hearts(const string &in slug)
{
    Entry@ e = Find(slug);
    if (e is null)
        return 0;
    return e.seedHearts + (Storage::Get("fake.heart." + slug, "") == "" ? 0 : 1);
}

bool Hearted(const string &in slug, const string &in steamId)
{
    return steamId != "" && Storage::Get("fake.heart." + slug, "") == steamId;
}

void SetHeart(const string &in slug, const string &in steamId, bool on)
{
    Storage::Set("fake.heart." + slug, on ? steamId : "");
}

// 0 when `steamId` may change the prefab, else the status the site answers: 401 signed res, 404 none, 403 not theirs.
int MayChange(const string &in slug, const string &in steamId, bool signedIn)
{
    if (!signedIn)
        return 401;
    Entry@ e = Find(slug);
    if (e is null)
        return 404;
    return e.uploaderId == steamId ? 0 : 403;
}

string RefusalJson(int status)
{
    if (status == 401)
        return "{\"error\":\"sign in with Steam\"}";
    if (status == 403)
        return "{\"error\":\"only its uploader can change it\"}";
    return "{\"error\":\"no such prefab\"}";
}

array<double>@ TimesOf(const string &in kind) { return kind == "uploads" ? uploadTimes : writeTimes; }

int RecentCount(const string &in kind)
{
    array<double>@ times = TimesOf(kind);
    for (int i = int(times.length()) - 1; i >= 0; i--)
        if (Host::Time() - times[i] > Server::HOUR)
            times.removeAt(uint(i));
    return int(times.length());
}

void Remember(const string &in kind) { TimesOf(kind).insertLast(Host::Time()); }

string FileOf(const string &in slug)
{
    Entry@ e = Find(slug);
    if (e is null)
        return "";
    if (e.seeded && Storage::Get("fake.f." + slug, "") == "")
        return Plugins::ReadFile("data/store/" + slug + ".json");
    return Replace(Storage::Get("fake.f." + slug, ""), NEWLINE, "\n");
}

// A new prefab, under the first free slug its name gives (as the site's addPrefab does).
string Add(const string &in name, const string &in description, const array<string>@ tags, const string &in file,
           const string &in uploaderId, const string &in uploaderName)
{
    Load();
    string base = Slug(name), slug = base;
    for (int n = 2; Find(slug) !is null || Storage::Get("fake.e." + slug, "") != ""; n++)
        slug = base + "-" + n;
    Entry e;
    e.slug = slug;
    e.name = Trim(name);
    e.description = Trim(description);
    e.tags = Join(tags, ",");
    e.uploaderId = uploaderId;
    e.uploaderName = uploaderName == "" ? uploaderId : uploaderName;
    e.created = e.updated = "today";
    entries.insertLast(e);
    SetFileOf(e, file);
    string list = Storage::Get("fake.added", "");
    Storage::Set("fake.added", list == "" ? slug : list + "|" + slug);
    return slug;
}

void SetFields(const string &in slug, const string &in name, const string &in description, const array<string>@ tags)
{
    Entry@ e = Find(slug);
    e.name = Trim(name);
    e.description = Trim(description);
    e.tags = Join(tags, ",");
    e.updated = "today";
    if (e.seeded)
        Storage::Set("fake.updated." + slug, e.updated);
    else
        SaveEntry(e);
}

string SetFile(const string &in slug, const string &in file)
{
    Entry@ e = Find(slug);
    e.updated = "today, v" + (parseInt(Storage::Get("fake.version." + slug, "1")) + 1);
    Storage::Set("fake.version." + slug, e.updated.substr(e.updated.findLast("v") + 1));
    SetFileOf(e, file);
    return e.updated;
}

void SetFileOf(Entry@ e, const string &in file)
{
    e.pieces = Json::Count(file, "items");
    e.bytes = int(file.length());
    e.size = Library::SizeOfFile(file);
    Storage::Set("fake.f." + e.slug, Replace(Replace(file, "\r", ""), "\n", NEWLINE));
    if (!e.seeded)
        SaveEntry(e);
}

void Remove(const string &in slug)
{
    Entry@ e = Find(slug);
    entries.removeAt(uint(entries.findByRef(e)));
    if (e.seeded)
    {
        string list = Storage::Get("fake.removed", "");
        Storage::Set("fake.removed", list == "" ? slug : list + "|" + slug);
    }
    else
    {
        array<string>@ added = Storage::Get("fake.added", "").split("|");
        int at = added.find(slug);
        if (at >= 0)
            added.removeAt(uint(at));
        Storage::Set("fake.added", Join(added, "|"));
        Storage::Set("fake.e." + slug, "");
    }
    Storage::Set("fake.f." + slug, "");
}

// The site's /api/prefab-list answer: the gallery's order (Popular: most hearts, newest first on a tie; Newest), one
// tag, every word of `q` in the name, description, uploader or a tag; a page from `cursor`, `next` after it or null.
string ListJson(const string &in sort, const string &in tag, const string &in q, int cursor, int limit)
{
    Load();
    array<Entry@> found;
    array<string>@ words = Lower(Trim(q)).split(" ");
    for (uint i = 0; i < entries.length(); i++)
    {
        Entry@ e = entries[i];
        if (tag != "" && e.tags.split(",").find(tag) < 0)
            continue;
        string text = Lower(e.name + "\n" + e.description + "\n" + e.uploaderName + "\n" + Replace(e.tags, ",", "\n"));
        bool all = true;
        for (uint w = 0; w < words.length() && all; w++)
            all = words[w] == "" || text.findFirst(words[w]) >= 0;
        if (all)
            found.insertLast(e);
    }
    // insertion sort, newest first (created strings compare in order; "today" sorts after every date)
    for (uint i = 1; i < found.length(); i++)
        for (uint j = i; j > 0 && Before(found[j - 1], found[j], sort); j--)
        {
            Entry@ t = found[j];
            @found[j] = found[j - 1];
            @found[j - 1] = t;
        }
    string items;
    int end = cursor + limit;
    for (int i = cursor; i < end && i < int(found.length()); i++)
        items += (items == "" ? "" : ",") + EntryJson(found[uint(i)]);
    return "{\"total\":" + found.length() + ",\"next\":" + (end < int(found.length()) ? "" + end : "null") + ",\"prefabs\":[" + items + "]}";
}

// whether `a` should come after `b`
bool Before(Entry@ a, Entry@ b, const string &in sort)
{
    if (sort == "popular" && Hearts(a.slug) != Hearts(b.slug))
        return Hearts(a.slug) < Hearts(b.slug);
    return NewestKey(a) < NewestKey(b);
}

string NewestKey(Entry@ e) { return e.created == "today" ? "9999" : e.created; }

string EntryJson(Entry@ e)
{
    array<string>@ size = e.size.split(",");
    string tags;
    array<string>@ t = e.tags.split(",");
    for (uint i = 0; i < t.length(); i++)
        if (t[i] != "")
            tags += (tags == "" ? "" : ",") + Json::Quote(t[i]);
    return "{\"slug\":" + Json::Quote(e.slug) + ",\"name\":" + Json::Quote(e.name) + ",\"description\":" + Json::Quote(e.description)
         + ",\"tags\":[" + tags + "],\"uploader\":{\"steamId\":" + Json::Quote(e.uploaderId) + ",\"name\":" + Json::Quote(e.uploaderName)
         + "},\"createdAt\":" + Json::Quote(e.created) + ",\"updatedAt\":" + Json::Quote(e.updated) + ",\"pieces\":" + e.pieces
         + ",\"bytes\":" + e.bytes + ",\"favorites\":" + Hearts(e.slug)
         + (size.length() == 3 ? ",\"size\":{\"w\":" + size[0] + ",\"d\":" + size[1] + ",\"h\":" + size[2] + "}" : ",\"size\":null")
         + ",\"thumb\":" + Json::Quote(e.seeded ? Plugins::Folder() + "data\\store\\" + e.slug + ".png" : "")
         + ",\"file\":" + Json::Quote("/api/prefabs/" + e.slug + "/file") + ",\"hearted\":" + (Hearted(e.slug, Server::signedInAs) ? "true" : "false") + "}";
}

}  // namespace FakeStore
