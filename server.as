// The prefab store's server, behind one set of calls, so the tab and the store never care which one answers: the site
// (ballestrecords.com: its prefab list, file, thumbnail and sign-in routes for the game) or, until those are live, a fake
// that answers exactly as the site's routes do (the same status codes and JSON) from data/store and this plugin's
// storage. Every call returns a Req at once; Server::Update() finishes them, a fake one after a short delay as a real
// one would take.

class Req
{
    bool done = false;
    int status = 0;             // the HTTP status; 0 when no answer came
    string body;                // the answer: JSON, or a prefab file's text
    string error;               // why it failed, in words for the player ("" when it didn't)
    double at = 0;              // fake: when it answers
    int net = 0;                // site: the Net request
}

namespace Server
{

const string SITE = "https://ballestrecords.com";
// The site's limits (ballestrecords.com's lib/prefabs.ts), which the fake keeps too.
const int HOURLY_UPLOADS = 5, HOURLY_WRITES = 60;
const double HOUR = 3600;

array<Req@> pending;
string token;                   // the session the site (or the fake) gave the game; "" before signing in
string signedInAs;              // its Steam ID

bool Fake() { return !UseSite; }

Req@ Answer(int status, const string &in body, double delay = 0.25)
{
    Req r;
    r.status = status;
    r.body = body;
    r.at = Host::Time() + delay;
    if (status >= 400)
        r.error = Json::String(body, "error", "");
    pending.insertLast(r);
    return r;
}

// A call the site can't take yet (its route isn't live, or the host can't send it): failed at once, saying so.
Req@ NotYet(const string &in what)
{
    Req r;
    r.done = true;
    r.status = 501;
    r.error = what + " isn't on ballestrecords.com yet: switch the store to its practice copy in this plugin's settings";
    return r;
}

void Update()
{
    for (int i = int(pending.length()) - 1; i >= 0; i--)
    {
        Req@ r = pending[i];
        if (r.net != 0)
        {
            if (!Net::Done(r.net))
                continue;
            r.status = Net::Status(r.net);
            r.body = Net::Body(r.net);
            if (r.status == 0)
                r.error = "couldn't reach ballestrecords.com: " + Net::Error(r.net);
            else if (r.status >= 400)
                r.error = Json::String(r.body, "error", "the site answered " + r.status);
            Net::Forget(r.net);
        }
        else if (Host::Time() < r.at)
            continue;
        r.done = true;
        pending.removeAt(uint(i));
    }
}

Req@ Get(const string &in path)
{
    Req r;
    r.net = Net::Get(SITE + path, token);
    if (r.net == 0)
    {
        r.done = true;
        r.error = Net::Refusal();
        return r;
    }
    pending.insertLast(r);
    return r;
}

// --- the calls ------------------------------------------------------------------------------------------------------

// GET /api/prefab-list: a page of the store. `sort` popular or newest, `tag` "" or one of TAGS, `q` words.
Req@ List(const string &in sort, const string &in tag, const string &in q, int cursor, int limit)
{
    string query = "?sort=" + sort + "&cursor=" + cursor + "&limit=" + limit;
    if (tag != "")
        query += "&tag=" + tag;
    if (q != "")
        query += "&q=" + UrlWords(q);
    if (!Fake())
        return Get("/api/prefab-list" + query);
    return Answer(200, FakeStore::ListJson(sort, tag, q, cursor, limit), 0.12);
}

// GET /api/prefabs/<slug>/file: a prefab's file, as uploaded.
Req@ File(const string &in slug)
{
    if (!Fake())
        return Get("/api/prefabs/" + slug + "/file");
    string text = FakeStore::FileOf(slug);
    if (text == "")
        return Answer(404, "{\"error\":\"no such prefab\"}");
    return Answer(200, text, 0.3);
}

// POST /api/auth/steam/ticket: the game signs in. The fake takes the player's Steam ID as Steam would vouch for it.
Req@ SignIn()
{
    if (!Fake())
        return NotYet("signing in from the game");          // needs the ticket's state polled first: Session below
    string me = Steam::OwnId();
    if (me == "")
        return Answer(502, "{\"error\":\"Steam didn't answer\"}");
    return Answer(200, "{\"id\":" + Json::Quote(me) + ",\"token\":" + Json::Quote("fake." + me) + ",\"expiresIn\":86400}", 0.4);
}

// GET /api/prefabs: how many uploads this hour the player has left.
Req@ Quota()
{
    if (!Fake())
        return Get("/api/prefabs");
    if (token == "")
        return Answer(200, "{\"signedIn\":false,\"banned\":false,\"left\":0,\"limit\":0,\"nextAt\":null}", 0.1);
    int left = HOURLY_UPLOADS - FakeStore::RecentCount("uploads");
    return Answer(200, "{\"signedIn\":true,\"banned\":false,\"left\":" + (left < 0 ? 0 : left) + ",\"limit\":" + HOURLY_UPLOADS
                           + ",\"nextAt\":null,\"writesLeft\":" + (HOURLY_WRITES - FakeStore::RecentCount("writes")) + "}", 0.1);
}

// POST /api/prefabs (the upload form): a new prefab, credited to the signed-in player.
Req@ Upload(const string &in name, const string &in description, const array<string>@ tags, const string &in file)
{
    if (!Fake())
        return NotYet("uploading from the game");
    if (token == "")
        return Answer(401, "{\"error\":\"sign in with Steam to upload\"}");
    string problem = FieldsProblem(name, description, tags);
    if (problem != "")
        return Answer(400, "{\"problems\":[" + Json::Quote(problem) + "]}");
    if (FakeStore::RecentCount("uploads") >= HOURLY_UPLOADS)
        return Answer(429, "{\"error\":\"that's your uploads for the last hour\",\"limit\":5}");
    string slug = FakeStore::Add(name, description, tags, file, signedInAs, Steam::PersonaName(signedInAs));
    FakeStore::Remember("uploads");
    return Answer(201, "{\"slug\":" + Json::Quote(slug) + "}", 0.6);
}

// PATCH /api/prefabs/<slug>: its uploader changes its name, description and tags.
Req@ Edit(const string &in slug, const string &in name, const string &in description, const array<string>@ tags)
{
    if (!Fake())
        return NotYet("editing from the game");
    int refused = FakeStore::MayChange(slug, signedInAs, token != "");
    if (refused != 0)
        return Answer(refused, FakeStore::RefusalJson(refused));
    string problem = FieldsProblem(name, description, tags);
    if (problem != "")
        return Answer(400, "{\"problems\":[" + Json::Quote(problem) + "]}");
    if (FakeStore::RecentCount("writes") >= HOURLY_WRITES)
        return Answer(429, "{\"error\":\"that's your hearts and edits for the last hour\"}");
    FakeStore::SetFields(slug, name, description, tags);
    FakeStore::Remember("writes");
    return Answer(200, "{\"slug\":" + Json::Quote(slug) + "}");
}

// PUT /api/prefabs/<slug>/file: its uploader publishes a new version of the file. Not on the site yet (its files
// can't change after upload); the fake has it, so the version flow can be tried.
Req@ UpdateFile(const string &in slug, const string &in file)
{
    if (!Fake())
        return NotYet("publishing a new version");
    int refused = FakeStore::MayChange(slug, signedInAs, token != "");
    if (refused != 0)
        return Answer(refused, FakeStore::RefusalJson(refused));
    if (FakeStore::RecentCount("writes") >= HOURLY_WRITES)
        return Answer(429, "{\"error\":\"that's your hearts and edits for the last hour\"}");
    string updated = FakeStore::SetFile(slug, file);
    FakeStore::Remember("writes");
    return Answer(200, "{\"slug\":" + Json::Quote(slug) + ",\"updatedAt\":" + Json::Quote(updated) + "}", 0.6);
}

// DELETE /api/prefabs/<slug>: its uploader takes it off the store.
Req@ Delete(const string &in slug)
{
    if (!Fake())
        return NotYet("deleting from the game");
    int refused = FakeStore::MayChange(slug, signedInAs, token != "");
    if (refused != 0)
        return Answer(refused, FakeStore::RefusalJson(refused));
    FakeStore::Remove(slug);
    return Answer(200, "{\"deleted\":" + Json::Quote(slug) + "}");
}

// PUT or DELETE /api/prefabs/<slug>/favorite: the player's heart, on or off.
Req@ Favorite(const string &in slug, bool on)
{
    if (!Fake())
        return NotYet("hearting from the game");
    if (token == "")
        return Answer(401, "{\"error\":\"sign in with Steam to favorite\"}");
    if (!FakeStore::Live(slug))
        return Answer(404, "{\"error\":\"no such prefab\"}");
    bool changes = FakeStore::Hearted(slug, signedInAs) != on;
    if (changes && FakeStore::RecentCount("writes") >= HOURLY_WRITES)
        return Answer(429, "{\"error\":\"that's your hearts and edits for the last hour\"}");
    if (changes)
    {
        FakeStore::SetHeart(slug, signedInAs, on);
        FakeStore::Remember("writes");
    }
    return Answer(200, "{\"on\":" + (on ? "true" : "false") + ",\"favorites\":" + FakeStore::Hearts(slug) + "}", 0.15);
}

// --- shared rules -----------------------------------------------------------------------------------------------------

const array<string> TAGS = {"Decoration", "Obstacle", "Ramp", "Loop", "Scenery", "Structure"};

// The site's checks on a name, description and tags (its checkFields), so a refusal reads the same.
string FieldsProblem(const string &in name, const string &in description, const array<string>@ tags)
{
    if (Trim(name) == "")
        return "Give it a name.";
    if (name.length() > 64)
        return "Keep the name to 64 characters.";
    if (description.length() > 500)
        return "Keep the description to 500 characters.";
    if (tags.length() > 3)
        return "Pick up to 3 tags.";
    for (uint i = 0; i < tags.length(); i++)
        if (TAGS.find(tags[i]) < 0)
            return tags[i] + " isn't one of the tags.";
    return "";
}

string UrlWords(const string &in text)
{
    string res;
    for (uint i = 0; i < text.length(); i++)
    {
        uint8 c = text[i];
        if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 || c == 95 || c == 46)
            res += text.substr(i, 1);
        else
        {
            string hex = "0123456789ABCDEF";
            res += "%" + hex.substr(c / 16, 1) + hex.substr(c % 16, 1);
        }
    }
    return res;
}

}  // namespace Server
