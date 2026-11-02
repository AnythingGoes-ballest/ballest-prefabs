// The site's pictures of its prefabs (its /api/prefabs/<slug>/thumb?v=<last edit> route), saved to this plugin's cache
// folder by the host (Net::SaveBody) so a window can show them, and remembered by slug and edit so a picture is fetched
// once per edit. They are fetched two at a time, at most 100 a minute (the host lets a plugin start 120 a minute: the
// rest are left for the list and store actions), in the order they were asked for: the top of the list first. One the
// host refuses (too many at once) waits a moment and is asked again.
// Also here: the hearts this player gave, which the site's list doesn't say (it's the same for everyone, cached a minute).

namespace Thumbs
{

const int PER_MINUTE = 100, AT_ONCE = 2;

array<string> queue;            // hrefs waiting
array<string> queueSlug;
array<string> fetchingHref, fetchingSlug;
array<int> nets;
array<double> starts;
double pausedUntil = 0;
int changes = 0;                // goes up whenever a picture arrives

// The picture of `slug` as of `href` (the list's "thumb"), a file; "" while it is fetched (or can't be).
string Path(const string &in slug, const string &in href)
{
    if (href == "" || !SafeSlug(slug))
        return "";
    array<string>@ kept = Storage::Get("thumb." + slug, "").split("|");
    if (kept.length() == 2 && kept[0] == href)
        return kept[1];
    if (kept.length() == 3 && kept[0] == href && kept[2] == "none")
        return "";
    if (fetchingHref.find(href) < 0 && queue.find(href) < 0)
    {
        queue.insertLast(href);
        queueSlug.insertLast(slug);
    }
    return "";
}

bool SafeSlug(const string &in slug)
{
    if (slug == "" || slug.length() > 80)
        return false;
    for (uint i = 0; i < slug.length(); i++)
    {
        uint8 c = slug[i];
        if (!((c >= 48 && c <= 57) || (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 45 || c == 95))
            return false;
    }
    return true;
}

// The edit's number in a thumb href ("...?v=1792189881317"), so each edit's picture is a file of its own.
string EditOf(const string &in href)
{
    int at = href.findLast("?v=");
    string v = at < 0 ? "" : href.substr(at + 3);
    for (uint i = 0; i < v.length(); i++)
        if (v[i] < 48 || v[i] > 57)
            return "0";
    return v == "" ? "0" : v;
}

void Update()
{
    for (int i = int(nets.length()) - 1; i >= 0; i--)
    {
        if (!Net::Done(nets[i]))
            continue;
        string href = fetchingHref[i], slug = fetchingSlug[i];
        int status = Net::Status(nets[i]);
        string path = status == 200 ? Net::SaveBody(nets[i], slug + "-" + EditOf(href) + ".png") : "";
        Net::Forget(nets[i]);
        nets.removeAt(uint(i));
        fetchingHref.removeAt(uint(i));
        fetchingSlug.removeAt(uint(i));
        if (path != "")
            Storage::Set("thumb." + slug, href + "|" + path);
        else if (status == 404)
            Storage::Set("thumb." + slug, href + "||none");     // the site can't draw it: not asked again
        // anything else (offline, a refusal) is asked again the next time the picture is wanted
        if (path != "")
            Library::NoteThumb(slug, path);
        changes++;
    }
    double now = Host::Time();
    while (queue.length() > 0 && int(nets.length()) < AT_ONCE && now >= pausedUntil)
    {
        while (starts.length() > 0 && now - starts[0] > 61)
            starts.removeAt(0);
        if (int(starts.length()) >= PER_MINUTE)
            return;
        int id = Net::Get(Server::SITE + queue[0]);
        if (id == 0)
        {
            pausedUntil = now + 2;                              // the host's limits: the same one again shortly
            return;
        }
        starts.insertLast(now);
        nets.insertLast(id);
        fetchingHref.insertLast(queue[0]);
        fetchingSlug.insertLast(queueSlug[0]);
        queue.removeAt(0);
        queueSlug.removeAt(0);
    }
}

// Pictures nobody waits for any more (the list changed): dropped from the queue.
void Clear()
{
    queue.resize(0);
    queueSlug.resize(0);
}

// --- the player's own hearts ---------------------------------------------------------------------------------------

bool Hearted(const string &in slug) { return Storage::Get("hearts", "|").findFirst("|" + slug + "|") >= 0; }

void SetHeart(const string &in slug, bool on)
{
    string all = Storage::Get("hearts", "|");
    all = Replace(all, "|" + slug + "|", "|");
    if (on)
        all += slug + "|";
    Storage::Set("hearts", all);
}

}  // namespace Thumbs
