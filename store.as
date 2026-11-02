// The prefab store: a window over the game (the tab's "open the prefab store", or "prefabs" in the footer).
//   prefab store  [browse] [my prefabs]  [search prefabs        ]     signed in as AnythingGoes  [close]
//   [popular] [newest]   [Decoration] [Obstacle] [Ramp] [Loop] [Scenery] [Structure]           13 prefabs
//   +----------------------------------------------------------------------------------------------------+
//   | [picture]  Wrong way sign                                           [♥ 2] [download]               |
//   |            by builder_a · Oct 5                                                                    |
//   |            59 pieces · 0.2 × 12.0 × 4.0 m · 38 KB · Decoration                                     |
//   +----------------------------------------------------------------------------------------------------+
// The search runs as it is typed (a moment after the last key), a page of 50 at a time, "show more" for the next.
// "my prefabs": what you've published and what is only on this PC, each published, updated or taken off the store.

namespace Store
{

UI::Window@ win;
UI::Window@ dim;                // the screen behind the store, darkened while it is open (a click on it closes the store)
int browseView, mineView, view;
UI::Button@ browseTab, mineTab, closeButton, popularButton, newestButton;
array<UI::Button@> tagChips;
UI::TextInput@ search;
UI::Text@ statusText, whoText, totalText;

string sort = "popular", tag = "";
const int PAGE = 50;

// browse
array<Card@> cards;
int next = -1, total = 0, seq = 0, askedSeq = 0;
Req@ listReq;
bool appending = false, dirty = true;
string askedFor;
double searchAt = 0;
array<UI::Button@> heartButtons, actionButtons;
array<UI::Image@> cardImages;
int shownThumbs = 0;
UI::Button@ moreButton;

// my prefabs
array<Library::Rec@> mineRecs;
array<UI::Button@> mineMain, mineSecond;
array<bool> mineConfirm;
Req@ quotaReq;
string quotaLine;
int shownChanges = -1;

void Build()
{
    @dim = UI::CreateWindow();
    dim.SetScreenSize(1, 1);
    dim.SetBackground(0, 0, 0, 0.6f);
    dim.SetBlocksClicks(true);
    dim.zOrder = 449;               // just behind the store
    dim.visible = false;
    @win = UI::CreateWindow();
    win.SetScreenSize(0.74f, 0.84f);
    win.SetBackground(WINDOW_R, WINDOW_G, WINDOW_B, 0.97f);
    win.SetCardBackground(CARD_R, CARD_G, CARD_B, 1);
    win.SetBlocksClicks(true);
    win.zOrder = 450;
    win.visible = false;
    win.StartHeader();
    win.AddText("prefab store", 28);
    win.AddSpace(16);
    @browseTab = win.AddButton("browse");
    @mineTab = win.AddButton("my prefabs");
    win.AddSpace(16);
    @search = win.AddTextInput(320, "search prefabs", 17);
    search.clearOnSubmit = false;
    win.AddSpace(0);
    @whoText = win.AddText("", 14);
    Muted(whoText);
    win.AddSpace(12);
    @closeButton = win.AddButton("close");
    Secondary(closeButton);
    win.NewRow();
    @popularButton = win.AddButton("popular");
    @newestButton = win.AddButton("newest");
    win.AddSpace(12);
    for (uint i = 0; i < Server::TAGS.length(); i++)
        tagChips.insertLast(win.AddButton(Server::TAGS[i]));
    win.AddSpace(0);
    @totalText = win.AddText("", 14);
    Muted(totalText);
    win.NewRow();
    @statusText = win.AddText("", 14);
    browseView = win.StartView();
    mineView = win.StartView();
    win.SetScrolling(browseView, true);
    win.SetScrolling(mineView, true);
    ShowTab(browseView);
    PaintFilters();
}

void ShowTab(int v)
{
    view = v;
    win.ShowView(v);
    if (v == browseView)
    {
        Primary(browseTab);
        Secondary(mineTab);
    }
    else
    {
        Secondary(browseTab);
        Primary(mineTab);
    }
    bool browse = v == browseView;
    search.visible = browse;
    popularButton.visible = browse;
    newestButton.visible = browse;
    totalText.visible = browse;
    for (uint i = 0; i < tagChips.length(); i++)
        tagChips[i].visible = browse;
    shownChanges = -1;
}

void PaintFilters()
{
    if (sort == "popular")
    {
        Primary(popularButton);
        Secondary(newestButton);
    }
    else
    {
        Secondary(popularButton);
        Primary(newestButton);
    }
    for (uint i = 0; i < tagChips.length(); i++)
        if (Server::TAGS[i] == tag)
            Primary(tagChips[i]);
        else
            Secondary(tagChips[i]);
}

void Open()
{
    dim.visible = true;
    win.visible = true;
    UI::SetCursorVisible(true);
    dirty = true;
    Sweep();
    @quotaReq = Server::Quota();
}

void OpenSearching(const string &in text)
{
    Open();
    ShowTab(browseView);
    search.value = text;
}

void Close()
{
    dim.visible = false;
    win.visible = false;
    UI::SetCursorVisible(false);
}

void Toggle()
{
    if (win.visible)
        Close();
    else
        Open();
}

void Refresh() { dirty = true; }

// Downloaded and published prefabs the store no longer has (the practice copy knows at once; the site would be asked).
void Sweep()
{
    if (!Server::Fake())
        return;
    for (uint i = 0; i < Library::recs.length(); i++)
    {
        Library::Rec@ r = Library::recs[i];
        bool gone = r.slug != "" && !FakeStore::Live(r.slug);
        if (gone != r.goneFromStore)
        {
            r.goneFromStore = gone;
            Library::Save(r);
            Jobs::changes++;
        }
    }
}

// --- browse -----------------------------------------------------------------------------------------------------------

void Ask(bool more)
{
    appending = more;
    askedFor = search.typed;
    askedSeq = ++seq;
    if (!more)
        Thumbs::Clear();
    @listReq = Server::List(sort, tag, askedFor, more ? next : 0, PAGE);
    dirty = false;
}

// What a card's button does: download it, get the store's newer version, or place the copy here.
string ActionOf(Card@ c)
{
    Library::Rec@ r = Library::BySlug(c.slug);
    if (r is null)
        return "download";
    if (!Library::Mine(r) && r.remoteUpdated != c.updatedAt)
        return "get the update";
    return Editor::IsOpen() ? "place" : "on this PC";
}

// The store's details onto what is here: hearts on one's own, a newer version of a download.
void NoteCards()
{
    for (uint i = 0; i < cards.length(); i++)
    {
        Library::Rec@ r = Library::BySlug(cards[i].slug);
        if (r is null)
            continue;
        bool changed = r.favorites != cards[i].favorites;
        r.favorites = cards[i].favorites;
        string newer = !Library::Mine(r) && r.remoteUpdated != cards[i].updatedAt ? cards[i].updatedAt : "";
        changed = changed || newer != r.storeUpdated;
        r.storeUpdated = newer;
        if (changed)
            Library::Save(r);
    }
}

void RebuildBrowse()
{
    win.ClearView(browseView);
    heartButtons.resize(0);
    actionButtons.resize(0);
    cardImages.resize(0);
    @moreButton = null;
    totalText.text = total + (total == 1 ? " prefab" : " prefabs");
    if (cards.length() == 0)
    {
        Muted(win.AddText(listReq !is null && !listReq.done ? "looking..." : "nothing matches", 16));
        return;
    }
    for (uint i = 0; i < cards.length(); i++)
    {
        Card@ c = cards[i];
        win.StartCard();
        cardImages.insertLast(win.AddImage(ThumbOf(c.thumb), 160, 100));
        win.AddText(c.name, 20);
        win.AddSpace(0);
        UI::Button@ heart = win.AddButton("♥ " + c.favorites);
        if (c.hearted)
            Primary(heart);
        else
            Secondary(heart);
        string action = ActionOf(c);
        UI::Button@ act = win.AddButton(action);
        if (action == "download")
            Primary(act);
        else if (action == "get the update")
            act.SetBackground(WARN_R * 0.4f, WARN_G * 0.4f, WARN_B * 0.4f, 1);
        else
            Secondary(act);
        win.NewRow();
        win.AddSpace(160);
        Muted(win.AddText("by " + c.uploaderName + " · " + DateText(c.createdAt), 14));
        win.NewRow();
        win.AddSpace(160);
        string size = SizeText(c.size);
        win.AddText(c.pieces + " pieces" + (size == "" ? "" : " · " + size) + " · " + FileSize(c.bytes)
                    + (c.tags == "" ? "" : " · " + Replace(c.tags, ",", ", ")), 14);
        if (c.description != "")
        {
            win.NewRow();
            win.AddSpace(160);
            Muted(win.AddText(Shorten(c.description, 110), 14));
        }
        win.EndCard();
        heartButtons.insertLast(heart);
        actionButtons.insertLast(act);
    }
    if (next >= 0)
    {
        win.NewRow();
        @moreButton = win.AddButton("show more");
        Secondary(moreButton);
    }
}

void UpdateBrowse()
{
    if (search.typed != askedFor)
    {
        if (searchAt == 0)
            searchAt = Host::Time() + 0.15;         // a moment after the last key
        if (Host::Time() >= searchAt)
        {
            searchAt = 0;
            dirty = true;
        }
    }
    if (dirty)
        Ask(false);
    if (listReq !is null && listReq.done)
    {
        Req@ r = listReq;
        @listReq = null;
        if (r.status == 200)
        {
            array<Card@> got = CardsOf(r.body);
            if (!appending)
                cards.resize(0);
            for (uint i = 0; i < got.length(); i++)
                cards.insertLast(got[i]);
            next = Json::Has(r.body, "next") && Json::String(r.body, "next") != "null" && Json::String(r.body, "next") != ""
                       ? int(Json::Number(r.body, "next")) : -1;
            total = int(Json::Number(r.body, "total"));
            NoteCards();
        }
        else
            Jobs::Say("couldn't read the store: " + r.error, true);
        RebuildBrowse();
        shownChanges = Jobs::changes;
    }
    if (Jobs::changes != shownChanges)
    {
        shownChanges = Jobs::changes;
        RebuildBrowse();
    }
    if (Thumbs::changes != shownThumbs)
    {
        // pictures that arrived: into their cards as they are
        shownThumbs = Thumbs::changes;
        for (uint i = 0; i < cards.length() && i < cardImages.length(); i++)
            if (cards[i].thumb == "" && cards[i].thumbHref != "")
            {
                cards[i].thumb = Thumbs::Path(cards[i].slug, cards[i].thumbHref);
                if (cards[i].thumb != "")
                    cardImages[i].path = cards[i].thumb;
            }
    }
    if (popularButton.Clicked() && sort != "popular")
    {
        sort = "popular";
        PaintFilters();
        dirty = true;
    }
    if (newestButton.Clicked() && sort != "newest")
    {
        sort = "newest";
        PaintFilters();
        dirty = true;
    }
    for (uint i = 0; i < tagChips.length(); i++)
        if (tagChips[i].Clicked())
        {
            tag = tag == Server::TAGS[i] ? "" : Server::TAGS[i];
            PaintFilters();
            dirty = true;
        }
    if (moreButton !is null && moreButton.Clicked() && next >= 0)
        Ask(true);
    for (uint i = 0; i < cards.length() && i < heartButtons.length(); i++)
    {
        Card@ c = cards[i];
        if (heartButtons[i].Clicked())
            Jobs::Start(Jobs::HEART, null, c, !c.hearted);
        if (actionButtons[i].Clicked())
        {
            string action = ActionOf(c);
            if (action == "download" || action == "get the update")
                Jobs::Start(Jobs::DOWNLOAD, null, c);
            else if (action == "place")
            {
                Close();
                Tab::PlaceRec(Library::BySlug(c.slug));
            }
        }
    }
}

// --- my prefabs ---------------------------------------------------------------------------------------------------------

void RebuildMine()
{
    win.ClearView(mineView);
    mineRecs.resize(0);
    mineMain.resize(0);
    mineSecond.resize(0);
    mineConfirm.resize(0);
    Muted(win.AddText(quotaLine, 14));
    array<string> titles = {"on the store", "only on this PC"};
    for (uint s = 0; s < 2; s++)
    {
        array<Library::Rec@> rows;
        for (uint i = 0; i < Library::recs.length(); i++)
        {
            Library::Rec@ r = Library::recs[i];
            if (s == 0 ? (r.slug != "" && Library::Mine(r)) : (r.slug == "" && r.source != Library::DOWNLOADED))
                rows.insertLast(r);
        }
        win.NewRow();
        win.AddText(titles[s], 20);
        Muted(win.AddText("" + rows.length(), 15));
        if (rows.length() == 0)
        {
            win.NewRow();
            Muted(win.AddText(s == 0 ? "nothing published yet" : "nothing here: make one from the prefabs tab in the editor", 14));
        }
        for (uint i = 0; i < rows.length(); i++)
        {
            Library::Rec@ r = rows[i];
            win.StartCard();
            win.AddImage(ThumbOf(r.thumb), 96, 60);
            win.AddText(r.name, 19);
            float red, green, blue;
            string badge = Tab::Badge(r, red, green, blue);
            win.AddText(badge, 14).SetColor(red, green, blue, 1);
            win.AddSpace(0);
            string main = s == 1 ? "publish" : (Library::CanPublishVersion(r) ? "publish update" : "see it in the store");
            UI::Button@ m = win.AddButton(main);
            if (main == "publish")
                Primary(m);
            else if (main == "publish update")
                Blue(m);
            else
                Secondary(m);
            UI::Button@ second = null;
            if (s == 0)
            {
                @second = win.AddButton("delete from the store");
                Danger(second);
            }
            win.NewRow();
            win.AddSpace(96);
            Muted(win.AddText(Tab::Meta(r) + (r.tags == "" ? " · no tags yet" : " · " + Replace(r.tags, ",", ", ")), 14));
            win.EndCard();
            mineRecs.insertLast(r);
            mineMain.insertLast(m);
            mineSecond.insertLast(second);
            mineConfirm.insertLast(false);
        }
    }
}

void UpdateMine()
{
    if (quotaReq !is null && quotaReq.done)
    {
        if (Json::Bool(quotaReq.body, "signedIn"))
            quotaLine = "uploads this hour: " + int(Json::Number(quotaReq.body, "left")) + " of " + int(Json::Number(quotaReq.body, "limit")) + " left"
                      + (Json::Has(quotaReq.body, "writesLeft") ? " · hearts and edits: " + int(Json::Number(quotaReq.body, "writesLeft")) + " of 60 left" : "");
        else
            quotaLine = "you sign in with Steam when you first publish, edit or heart something";
        @quotaReq = null;
        shownChanges = -1;
    }
    if (Jobs::changes != shownChanges)
    {
        if (shownChanges >= 0 && Server::token != "")
            @quotaReq = Server::Quota();
        shownChanges = Jobs::changes;
        RebuildMine();
    }
    for (uint i = 0; i < mineRecs.length(); i++)
    {
        Library::Rec@ r = mineRecs[i];
        if (mineMain[i].Clicked())
        {
            if (r.slug == "")
                Jobs::Start(Jobs::PUBLISH, r);
            else if (Library::CanPublishVersion(r))
                Jobs::Start(Jobs::UPDATE, r);
            else
            {
                ShowTab(browseView);
                search.value = r.name;
            }
        }
        if (mineSecond[i] !is null && mineSecond[i].Clicked())
        {
            if (!mineConfirm[i])
            {
                mineConfirm[i] = true;
                mineSecond[i].label = "click again to delete";
            }
            else
                Jobs::Start(Jobs::UNPUBLISH, r);
        }
    }
}

// --- each frame -------------------------------------------------------------------------------------------------------

void Update()
{
    if (!win.visible)
        return;
    if (closeButton.Clicked() || (Input::Pressed(Input::Escape) && !search.focused)
        || (Input::Pressed(Input::MouseLeft) && !win.hovered))
    {
        Close();
        return;
    }
    statusText.text = Jobs::message;
    if (Jobs::messageBad)
        statusText.SetColor(BAD_R, BAD_G, BAD_B, 1);
    else
        statusText.SetColor(LIME_R, LIME_G, LIME_B, 1);
    whoText.text = Server::token != "" ? "signed in as " + Steam::PersonaName(Server::signedInAs)
                 : (Server::Fake() ? "practice store · " : "") + "signs in with Steam when you publish";
    if (browseTab.Clicked() && view != browseView)
        ShowTab(browseView);
    if (mineTab.Clicked() && view != mineView)
    {
        ShowTab(mineView);
        @quotaReq = Server::Quota();
    }
    if (view == browseView)
        UpdateBrowse();
    else
        UpdateMine();
}

}  // namespace Store
