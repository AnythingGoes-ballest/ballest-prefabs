// Prefabs: the game's prefabs (groups of editor pieces saved as files) in the track editor and a store to share them.
//   - a tab of its own in the editor's left panel: your prefabs (made here and only here, published, downloaded), each
//     placed with one click as the game's own spawn places it (one group, selected), moved as Create Extensions places
//     new pieces; a new one made from the selection; one replaced with the selection, its old file kept as a version.
//   - the prefab store (its button in the tab, and "prefabs" in the footer): browse, search and download everyone's;
//     publish and delete your own. It talks to ballestrecords.com, or to a practice copy of the store kept in this
//     plugin (the "Use ballestrecords.com" setting off).
// Every store action that changes something signs in first: a Steam ticket the site checks, answered with a token.

[Setting name="Use ballestrecords.com" description="On: the real store. Off: a practice copy kept on this PC, where nothing you do leaves this PC."]
bool UseSite = true;

// Colours (the game's widget colours are linear: each is the linear value of the colour in its comment)
const float WINDOW_R = 0.0052f, WINDOW_G = 0.0060f, WINDOW_B = 0.0086f;     // #101217
const float CARD_R = 0.0116f, CARD_G = 0.0137f, CARD_B = 0.0194f;           // #1c1f26
const float BUTTON_R = 0.0232f, BUTTON_G = 0.0273f, BUTTON_B = 0.0382f;     // #2a2e37
const float PRIMARY_R = 0.0782f, PRIMARY_G = 0.2051f, PRIMARY_B = 0.0048f;  // #4f7d0f
const float LIME_R = 0.5647f, LIME_G = 0.9047f, LIME_B = 0.0319f;           // #c6f432
const float MUTED_R = 0.2582f, MUTED_G = 0.2747f, MUTED_B = 0.3185f;        // #8b8f99
const float BLUE_R = 0.0284f, BLUE_G = 0.1590f, BLUE_B = 0.4342f;           // #2f6fb0
const float WARN_R = 0.8879f, WARN_G = 0.5333f, WARN_B = 0.0762f;           // #f2c14e
const float BAD_R = 1.0f, BAD_G = 0.1714f, BAD_B = 0.147f;                  // #ff736b

void Muted(UI::Text@ t) { t.SetColor(MUTED_R, MUTED_G, MUTED_B, 1); }
void Primary(UI::Button@ b) { b.SetBackground(PRIMARY_R, PRIMARY_G, PRIMARY_B, 1); }
void Secondary(UI::Button@ b) { b.SetBackground(BUTTON_R, BUTTON_G, BUTTON_B, 1); }
void Blue(UI::Button@ b) { b.SetBackground(BLUE_R, BLUE_G, BLUE_B, 1); }
void Danger(UI::Button@ b) { b.SetBackground(0.2f, 0.02f, 0.02f, 1); }

UI::FooterButton@ footerButton;

void Main()
{
    Library::Load();
    Tab::Build();
    Store::Build();
    @footerButton = UI::AddFooterButton("prefabs");
    Log::Info("prefabs ready: " + Library::recs.length() + " on this PC, the store " + (UseSite ? "ballestrecords.com" : "a practice copy"));
}

void Update(float dt)
{
    Library::MeasureSome();
    Server::Update();
    Jobs::Update();
    if (!Server::Fake())
        Thumbs::Update();
    if (footerButton.Clicked())
        Store::Toggle();
    Tab::Update();
    Store::Update();
}

void OnSettingsChanged()
{
    Server::token = "";
    Store::Refresh();
}

// --- a store page's cards -----------------------------------------------------------------------------------------

// One prefab as the store lists it (the site's /api/prefab-list entry).
class Card
{
    string slug, name, description, tags, uploaderId, uploaderName, createdAt, updatedAt, size, thumb, thumbHref;
    int pieces = 0, bytes = 0, favorites = 0;
    bool hearted = false;
}

array<Card@> CardsOf(const string &in body)
{
    array<Card@> res;
    int n = Json::Count(body, "prefabs");
    for (int i = 0; i < n; i++)
    {
        string at = "prefabs." + i + ".";
        Card c;
        c.slug = Json::String(body, at + "slug");
        c.name = Json::String(body, at + "name");
        c.description = Json::String(body, at + "description");
        array<string> tags;
        for (int t = 0; t < Json::Count(body, at + "tags"); t++)
            tags.insertLast(Json::String(body, at + "tags." + t));
        c.tags = Join(tags, ",");
        c.uploaderId = Json::String(body, at + "uploader.steamId");
        c.uploaderName = Json::String(body, at + "uploader.name");
        c.createdAt = Json::String(body, at + "createdAt");
        c.updatedAt = Json::String(body, at + "updatedAt");
        c.pieces = int(Json::Number(body, at + "pieces"));
        c.bytes = int(Json::Number(body, at + "bytes"));
        c.favorites = int(Json::Number(body, at + "favorites"));
        // the practice store says; the site's list is the same for everyone, so this PC remembers the hearts it gave
        c.hearted = Server::Fake() ? Json::Bool(body, at + "hearted") : Thumbs::Hearted(c.slug);
        if (Json::Has(body, at + "size.w"))
            c.size = OneDecimal(Json::Number(body, at + "size.w")) + "," + OneDecimal(Json::Number(body, at + "size.d")) + ","
                    + OneDecimal(Json::Number(body, at + "size.h"));
        // the practice store's pictures are files; the site's are its thumbnail route, saved to a file (Thumbs)
        string thumb = Json::String(body, at + "thumb");
        if (Server::Fake())
            c.thumb = thumb.length() > 2 && thumb.substr(1, 1) == ":" ? thumb : "";
        else
        {
            c.thumbHref = thumb;
            c.thumb = Thumbs::Path(c.slug, thumb);
        }
        res.insertLast(c);
    }
    return res;
}

// A picture's file; without one, the "no picture yet" picture where there is room for its words, else a plain dark box.
string ThumbOf(const string &in path, bool big = false) { return path != "" ? path : (big ? Plugins::Folder() + "data\\no-picture.png" : ""); }

// A line that wraps at `width` (layout units) instead of running past its card or panel.
UI::Text@ Wrapped(UI::Text@ t, float width)
{
    t.SetWidth(width);
    t.SetWrap(true);
    return t;
}

// --- jobs: store actions, signed in first -------------------------------------------------------------------------

namespace Jobs
{

const int PUBLISH = 1, UPDATE = 2, EDIT = 3, UNPUBLISH = 4, HEART = 5, DOWNLOAD = 6;

class Job
{
    int kind = 0;
    Library::Rec@ rec;
    Card@ card;
    bool on = false;            // HEART: on or off
    Req@ req;
    bool signingIn = false, retried = false;
}

array<Job@> queue;
string message;                 // the last outcome, for the tab and the store
bool messageBad = false;
int changes = 0;                // goes up whenever a job finishes: the lists rebuild

void Start(int kind, Library::Rec@ rec, Card@ card = null, bool on = false)
{
    Job j;
    j.kind = kind;
    @j.rec = rec;
    @j.card = card;
    j.on = on;
    queue.insertLast(j);
    Say(Verb(kind) + "...", false);
}

bool Busy() { return queue.length() > 0; }

string Verb(int kind)
{
    switch (kind)
    {
        case PUBLISH: return "publishing";
        case UPDATE: return "publishing the new version";
        case EDIT: return "saving its details on the store";
        case UNPUBLISH: return "deleting it from the store";
        case HEART: return "saving your heart";
        case DOWNLOAD: return "downloading";
    }
    return "";
}

void Say(const string &in text, bool bad)
{
    message = text;
    messageBad = bad;
}

void Update()
{
    if (queue.length() == 0)
        return;
    Job@ j = queue[0];
    if (j.req is null)
    {
        // what changes something needs a session; downloads don't
        if (j.kind != DOWNLOAD && Server::token == "")
        {
            j.signingIn = true;
            @j.req = Server::SignIn();
        }
        else
            @j.req = Send(j);
        return;
    }
    if (!j.req.done)
        return;
    if (j.signingIn)
    {
        j.signingIn = false;
        if (j.req.status != 200)
            { Finish(j, "couldn't sign in with Steam: " + j.req.error); return; }
        Server::token = Json::String(j.req.body, "token");
        Server::signedInAs = Json::String(j.req.body, "id");
        @j.req = Send(j);
        return;
    }
    // a session that expired (a day) or was refused: sign in again, once
    if (j.req.status == 401 && !j.retried && j.kind != DOWNLOAD)
    {
        j.retried = true;
        Server::token = "";
        @j.req = null;
        return;
    }
    if (j.req.status < 200 || j.req.status >= 300)
    {
        string why = j.req.error;
        int problems = Json::Count(j.req.body, "problems");
        for (int i = 0; i < problems; i++)
            why += (why == "" ? "" : " ") + Json::String(j.req.body, "problems." + i);
        { Finish(j, "couldn't finish " + Verb(j.kind) + ": " + (why == "" ? "the store answered " + j.req.status : why)); return; }
    }
    Done(j);
}

Req@ Send(Job@ j)
{
    array<string> tags;
    if (j.rec !is null)
        tags = j.rec.tags.split(",");
    for (int i = int(tags.length()) - 1; i >= 0; i--)
        if (tags[i] == "")
            tags.removeAt(uint(i));
    switch (j.kind)
    {
        case PUBLISH: return Server::Upload(j.rec.name, j.rec.description, tags, Prefabs::Read(j.rec.file));
        case UPDATE: return Server::UpdateFile(j.rec.slug, Prefabs::Read(j.rec.file));
        case EDIT: return Server::Edit(j.rec.slug, j.rec.name, j.rec.description, tags);
        case UNPUBLISH: return Server::Delete(j.rec.slug);
        case HEART: return Server::Favorite(j.card.slug, j.on);
        case DOWNLOAD: return Server::File(j.card.slug);
    }
    return null;
}

void Done(Job@ j)
{
    Library::Rec@ r = j.rec;
    switch (j.kind)
    {
        case PUBLISH:
            r.slug = Json::String(j.req.body, "slug");
            r.source = Library::MINE;
            r.uploaderId = Server::signedInAs;
            r.uploaderName = Steam::PersonaName(Server::signedInAs);
            r.publishedHash = Library::Hash(Prefabs::Read(r.file));
            r.remoteUpdated = "today";
            if (Server::Fake())
                r.thumb = "";
            Library::Save(r);
            { Finish(j, "“" + r.name + "” is on the store", false); return; }
        case UPDATE:
            r.publishedHash = Library::Hash(Prefabs::Read(r.file));
            r.remoteUpdated = Json::String(j.req.body, "updatedAt");
            Library::Save(r);
            { Finish(j, "the store has this version of “" + r.name + "” now", false); return; }
        case EDIT:
            { Finish(j, "saved “" + r.name + "” on the store", false); return; }
        case UNPUBLISH:
            r.slug = "";
            r.source = Library::LOCAL;
            r.publishedHash = r.remoteUpdated = "";
            Library::Save(r);
            { Finish(j, "“" + r.name + "” is off the store; it's still on this PC", false); return; }
        case HEART:
            j.card.hearted = Json::Bool(j.req.body, "on");
            if (!Server::Fake())
                Thumbs::SetHeart(j.card.slug, j.card.hearted);
            j.card.favorites = int(Json::Number(j.req.body, "favorites"));
            {
                // the copy on this PC (published by you, or downloaded) shows the new count at once
                Library::Rec@ here = Library::BySlug(j.card.slug);
                if (here !is null && here.favorites != j.card.favorites)
                {
                    here.favorites = j.card.favorites;
                    Library::Save(here);
                }
            }
            { Finish(j, "", false); return; }
        case DOWNLOAD:
        {
            Library::Rec@ made;
            string kept = Library::KeepDownload(j.card.slug, j.req.body, made);
            if (kept != "")
                { Finish(j, "couldn't save it: " + kept); return; }
            Card@ c = j.card;
            made.slug = c.slug;
            made.name = c.name;
            made.description = c.description;
            made.tags = c.tags;
            made.uploaderId = c.uploaderId;
            made.uploaderName = c.uploaderName;
            made.remoteUpdated = c.updatedAt;
            made.favorites = c.favorites;
            made.thumb = c.thumb;
            made.source = c.uploaderId != "" && c.uploaderId == Steam::OwnId() ? Library::MINE : Library::DOWNLOADED;
            if (c.size != "")
                made.size = c.size;
            Library::Save(made);
            { Finish(j, "“" + c.name + "” is on this PC: place it from the prefabs tab", false); return; }
        }
    }
}

void Finish(Job@ j, const string &in text, bool bad = true)
{
    queue.removeAt(0);
    if (text != "" || bad)
        Say(text, bad);
    else if (queue.length() == 0)
        Say("", false);
    changes++;
}

}  // namespace Jobs
