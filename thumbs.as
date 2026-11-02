// The site's pictures of its prefabs (its /api/prefabs/<slug>/thumb?v=<last edit> route), saved to this plugin's cache
// folder by the host (Net::SaveBody) so a window can show them, and remembered by slug and edit so a picture is fetched
// once per edit. They are fetched one at a time, at most 24 a minute (the host lets a plugin start 30 requests a minute:
// the rest are left for the list and store actions), in the order they were asked for: the top of the list first.
// Also here: the hearts this player gave, which the site's list doesn't say (it's the same for everyone, cached a minute).

namespace Thumbs
{

const int PER_MINUTE = 24;

array<string> queue;            // hrefs waiting
array<string> queueSlug;
string fetchingHref, fetchingSlug;
int net = 0;
array<double> starts;
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
    if (href != fetchingHref && queue.find(href) < 0)
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
    if (net != 0)
    {
        if (!Net::Done(net))
            return;
        int status = Net::Status(net);
        string path = status == 200 ? Net::SaveBody(net, fetchingSlug + "-" + EditOf(fetchingHref) + ".png") : "";
        Net::Forget(net);
        net = 0;
        if (path != "")
            Storage::Set("thumb." + fetchingSlug, fetchingHref + "|" + path);
        else if (status == 404)
            Storage::Set("thumb." + fetchingSlug, fetchingHref + "||none");     // the site can't draw it: not asked again
        // anything else (offline, a refusal) is asked again the next time the picture is wanted
        if (path != "")
            Library::NoteThumb(fetchingSlug, path);
        fetchingHref = fetchingSlug = "";
        changes++;
    }
    if (queue.length() == 0)
        return;
    double now = Host::Time();
    while (starts.length() > 0 && now - starts[0] > 61)
        starts.removeAt(0);
    if (int(starts.length()) >= PER_MINUTE)
        return;
    fetchingHref = queue[0];
    fetchingSlug = queueSlug[0];
    queue.removeAt(0);
    queueSlug.removeAt(0);
    net = Net::Get(Server::SITE + fetchingHref);
    starts.insertLast(now);
    if (net == 0)
        fetchingHref = fetchingSlug = "";
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
