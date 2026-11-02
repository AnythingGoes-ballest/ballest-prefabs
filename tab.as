// The prefabs tab in the editor's left panel (Window.DockInEditorTab: a fifth button after the game's four), a quick
// view to find a prefab and place it:
//   prefabs                              [cart] [+]
//   [ filter my prefabs             ]
//   v local only 2
//     [pic] loop gate               [more]      (a click anywhere on the card but "more" places it)
//   > published by you 2   (folded)
//   v downloaded 3 ...
// The cart opens the store, + the form for a new prefab from the selection (name, description, tags, checked against
// the game's rules). "more" opens a prefab's page (place, replace with the selection, edit, picture, publish,
// versions, delete). Each section folds; which are folded is kept.
// Widths are layout units: the tab's panel has about 330 for its content, a card's text beside its picture 222.
const float PANEL_W = 330, CARD_TEXT_W = 222, CARD_NAME_W = 150;

namespace Tab
{

UI::Window@ win;
int listView, formView, detailView;
UI::Text@ statusText;
UI::Button@ createButton, storeButton;
UI::TextInput@ filterInput;

// the list
array<Library::Rec@> rowRecs;
array<int> rowCards;
array<UI::Button@> moreButtons, foldButtons;
string shownFilter;
int shownChanges = -1, listChanges = -1;
bool listDirty = true;
string shownFiles;
double nextReconcile = 0;

// the form (a new prefab, or one's details edited)
UI::Text@ formTitle, checksText;
UI::TextInput@ nameInput, descriptionInput;
array<UI::Button@> tagButtons;
array<bool> tagOn;
UI::Button@ saveButton, savePublishButton, cancelButton;
Library::Rec@ editing;          // null while making a new one

// a prefab's page
Library::Rec@ shown;
UI::Button@ backButton, placeButton, replaceButton, editButton, publishButton, unpublishButton, deleteButton, storeButton2, pictureButton;
// a picture from the editor's view: the selection let go first (its highlight and gizmo would be in it), a frame
// later the capture, then waiting for it
int pictureStep = 0;
double pictureAt = 0;
Library::Rec@ pictureOf;
array<int> pictureSelection;    // selected again once the picture is taken
bool pictureQuiet = false;      // taken as a new prefab is saved: the save's own message stays
UI::Text@ pictureHint;
array<UI::Button@> putBackButtons;
bool confirmReplace = false, confirmDelete = false, confirmUnpublish = false;
int view = 0;

void Build()
{
    @win = UI::CreateWindow();
    win.DockInEditorTab(Plugins::Folder() + "tab.png");
    win.SetBackground(0, 0, 0, 0);
    win.SetCardBackground(CARD_R, CARD_G, CARD_B, 1);
    win.StartHeader();
    win.AddText("prefabs", 26);
    win.AddSpace(0);
    @storeButton = win.AddIconButton(Plugins::Folder() + "cart.png");
    storeButton.SetSize(30, 44);
    storeButton.SetTooltip("open the prefab store");
    Secondary(storeButton);
    @createButton = win.AddIconButton(Plugins::Folder() + "plus.png");
    createButton.SetSize(30, 44);
    createButton.SetTooltip("create a prefab from the selection");
    Primary(createButton);
    win.NewRow();
    @filterInput = win.AddTextInput(0, "filter my prefabs", 15);
    filterInput.clearOnSubmit = false;
    win.NewRow();
    @statusText = Wrapped(win.AddText("", 13), PANEL_W);
    statusText.visible = false;
    listView = win.StartView();
    formView = win.StartView();
    BuildForm();
    detailView = win.StartView();
    Show(listView);
}

void Show(int v)
{
    view = v;
    win.ShowView(v);
    bool list = v == listView;
    if (list)
        listDirty = true;
    createButton.visible = list;
    storeButton.visible = list;
    filterInput.visible = list;
}

// --- the list ---------------------------------------------------------------------------------------------------------

string Badge(Library::Rec@ r, float &out red, float &out green, float &out blue)
{
    red = MUTED_R;
    green = MUTED_G;
    blue = MUTED_B;
    if (r.goneFromStore)
    {
        red = BAD_R; green = BAD_G; blue = BAD_B;
        return r.source == Library::DOWNLOADED ? "removed from the store" : "off the store";
    }
    if (r.slug == "")
        return "not published";
    if (Library::Mine(r))
    {
        if (Library::ChangedHere(r))
        {
            red = 0.25f; green = 0.55f; blue = 1;
            return "changed here · publish update";
        }
        red = LIME_R; green = LIME_G; blue = LIME_B;
        return "live · ♥ " + r.favorites;
    }
    if (r.storeUpdated != "")
    {
        red = WARN_R; green = WARN_G; blue = WARN_B;
        return "update on the store";
    }
    return "by " + Shorten(r.uploaderName, 18);
}

string Meta(Library::Rec@ r)
{
    string size = SizeText(r.size);
    return r.pieces + " pieces" + (size == "" ? "" : " · " + size);
}

bool Matches(Library::Rec@ r, const string &in filter)
{
    if (Trim(filter) == "")
        return true;
    string text = Lower(r.name + " " + r.description + " " + r.tags + " " + r.uploaderName);
    array<string>@ words = Lower(Trim(filter)).split(" ");
    for (uint i = 0; i < words.length(); i++)
        if (words[i] != "" && text.findFirst(words[i]) < 0)
            return false;
    return true;
}

void RebuildList()
{
    shownFilter = filterInput.typed;
    listChanges = Jobs::changes;
    listDirty = false;
    win.ClearView(listView);
    rowRecs.resize(0);
    rowCards.resize(0);
    moreButtons.resize(0);
    foldButtons.resize(0);
    array<string> titles = {"local only", "published by you", "downloaded"};
    for (uint s = 0; s < 3; s++)
    {
        array<Library::Rec@> rows;
        for (uint i = 0; i < Library::recs.length(); i++)
        {
            Library::Rec@ r = Library::recs[i];
            uint section = r.slug == "" && r.source != Library::DOWNLOADED ? 0 : (Library::Mine(r) ? 1 : 2);
            if (section == s && Matches(r, shownFilter))
                rows.insertLast(r);
        }
        bool folded = Folded(int(s));
        win.NewRow();
        UI::Button@ fold = win.AddIconButton(folded ? "play" : "down");
        fold.SetSize(26, 22);
        fold.SetTooltip(folded ? "show " + titles[s] : "fold " + titles[s]);
        fold.SetBackground(0, 0, 0, 0);
        foldButtons.insertLast(fold);
        win.AddText(titles[s], 19);
        Muted(win.AddText("" + rows.length(), 14));
        if (folded)
            continue;
        if (rows.length() == 0)
        {
            win.NewRow();
            Muted(win.AddText(s == 0 ? "none: select pieces and press +" : (s == 1 ? "none yet" : "none: find some in the store"), 13));
        }
        for (uint i = 0; i < rows.length(); i++)
        {
            Library::Rec@ r = rows[i];
            int card = win.StartCard(true);
            win.AddImage(ThumbOf(r.thumb), 64, 40);
            Wrapped(win.AddText(Shorten(r.name, 40), 16), CARD_NAME_W);
            win.AddSpace(0);
            UI::Button@ more = win.AddButton("more");
            Secondary(more);
            win.EndCard();
            rowRecs.insertLast(r);
            rowCards.insertLast(card);
            moreButtons.insertLast(more);
        }
    }
}

// --- the form ---------------------------------------------------------------------------------------------------------

void BuildForm()
{
    @formTitle = win.AddText("new prefab", 22);
    win.NewRow();
    Muted(win.AddText("name", 13));
    win.NewRow();
    @nameInput = win.AddTextInput(0, "a name for it", 16);
    nameInput.clearOnSubmit = false;
    win.NewRow();
    Muted(win.AddText("description", 13));
    win.NewRow();
    @descriptionInput = win.AddTextInput(0, "what it is (optional)", 14);
    descriptionInput.clearOnSubmit = false;
    win.NewRow();
    Muted(win.AddText("tags (up to 3)", 13));
    for (uint i = 0; i < Server::TAGS.length(); i++)
    {
        if (i % 3 == 0)
            win.NewRow();
        UI::Button@ b = win.AddButton(Server::TAGS[i]);
        tagButtons.insertLast(b);
        tagOn.insertLast(false);
    }
    win.NewRow();
    @checksText = Wrapped(win.AddText("", 13), PANEL_W);
    win.NewRow();
    @pictureHint = Wrapped(win.AddText("saving takes its picture from the editor's view: frame it first (the middle of the view, without the panels). You can take a new one from its page later.", 12), PANEL_W);
    Muted(pictureHint);
    win.NewRow();
    @saveButton = win.AddButton("save to my prefabs");
    Primary(saveButton);
    win.NewRow();
    @savePublishButton = win.AddButton("save and publish");
    Blue(savePublishButton);
    win.NewRow();
    @cancelButton = win.AddButton("cancel");
    Secondary(cancelButton);
}

void OpenForm(Library::Rec@ r)
{
    @editing = r;
    formTitle.text = r is null ? "new prefab" : "edit details";
    nameInput.value = r is null ? "" : r.name;
    descriptionInput.value = r is null ? "" : r.description;
    array<string> tags;
    if (r !is null)
        tags = r.tags.split(",");
    for (uint i = 0; i < tagButtons.length(); i++)
        tagOn[i] = tags.find(Server::TAGS[i]) >= 0;
    PaintTags();
    savePublishButton.visible = r is null;
    pictureHint.visible = r is null;
    saveButton.label = r is null ? "save to my prefabs" : (r.slug != "" && Library::Mine(r) ? "save here and on the store" : "save");
    Show(formView);
    nameInput.Focus();
}

void PaintTags()
{
    for (uint i = 0; i < tagButtons.length(); i++)
        if (tagOn[i])
            Primary(tagButtons[i]);
        else
            Secondary(tagButtons[i]);
}

array<string> ChosenTags()
{
    array<string> res;
    for (uint i = 0; i < tagButtons.length(); i++)
        if (tagOn[i])
            res.insertLast(Server::TAGS[i]);
    return res;
}

// The selection against the game's prefab rules (2 to 4096 pieces, never the start pad), as the form shows it.
string SelectionProblem(int &out count)
{
    array<int>@ sel = Editor::Selection();
    count = int(sel.length());
    if (count < 2)
        return "select at least 2 pieces";
    if (count > 4096)
        return "the game takes at most 4,096 pieces";
    for (uint i = 0; i < sel.length(); i++)
        if (Editor::PieceClass(sel[i]) == "MP_PlayerStart_C")
            return "the start pad is selected: the game won't place a prefab with it";
    return "";
}

void UpdateForm()
{
    int count;
    string problem = editing is null ? SelectionProblem(count) : "";
    string fields = Server::FieldsProblem(nameInput.typed, descriptionInput.typed, ChosenTags());
    if (editing is null)
    {
        checksText.text = problem != "" ? problem : (fields != "" ? fields : "✓ " + count + " pieces, checked against the game's rules");
        if (problem != "" || fields != "")
            checksText.SetColor(WARN_R, WARN_G, WARN_B, 1);
        else
            checksText.SetColor(LIME_R, LIME_G, LIME_B, 1);
    }
    else
    {
        checksText.text = fields;
        checksText.SetColor(WARN_R, WARN_G, WARN_B, 1);
    }
    for (uint i = 0; i < tagButtons.length(); i++)
        if (tagButtons[i].Clicked())
        {
            if (tagOn[i] || ChosenTags().length() < 3)
                tagOn[i] = !tagOn[i];
            PaintTags();
        }
    bool publish = savePublishButton.Clicked();
    if (cancelButton.Clicked())
    {
        Show(editing is null ? listView : detailView);
        return;
    }
    if (!(saveButton.Clicked() || publish) || problem != "" || fields != "")
        return;
    if (editing is null)
    {
        Library::Rec@ made;
        string failed = Library::Create(nameInput.typed, descriptionInput.typed, ChosenTags(), made);
        if (failed != "")
        {
            Jobs::Say(failed, true);
            return;
        }
        Jobs::Say("saved “" + made.name + "” on this PC", false);
        if (publish)
            Jobs::Start(Jobs::PUBLISH, made);
        StartPicture(made, true);
        OpenDetail(made);
    }
    else
    {
        editing.name = Trim(nameInput.typed);
        editing.description = Trim(descriptionInput.typed);
        editing.tags = Join(ChosenTags(), ",");
        Library::Save(editing);
        if (editing.slug != "" && Library::Mine(editing))
            Jobs::Start(Jobs::EDIT, editing);
        else
            Jobs::Say("saved “" + editing.name + "”", false);
        OpenDetail(editing);
    }
}

// --- a prefab's page ----------------------------------------------------------------------------------------------------

void OpenDetail(Library::Rec@ r)
{
    @shown = r;
    confirmReplace = confirmDelete = confirmUnpublish = false;
    RebuildDetail();
    Show(detailView);
}

void RebuildDetail()
{
    win.ClearView(detailView);
    putBackButtons.resize(0);
    Library::Rec@ r = shown;
    @backButton = win.AddButton("‹ prefabs");
    Secondary(backButton);
    win.NewRow();
    win.AddImage(ThumbOf(r.thumb, true), 240, 150);
    win.NewRow();
    Wrapped(win.AddText(r.name, 22), PANEL_W);
    win.NewRow();
    float red, green, blue;
    string badge = Badge(r, red, green, blue);
    Wrapped(win.AddText(badge, 13), PANEL_W).SetColor(red, green, blue, 1);
    win.NewRow();
    Muted(Wrapped(win.AddText(Meta(r) + " · " + FileSize(r.bytes), 13), PANEL_W));
    if (r.tags != "")
    {
        win.NewRow();
        Muted(Wrapped(win.AddText(Replace(r.tags, ",", ", "), 13), PANEL_W));
    }
    if (r.description != "")
    {
        win.NewRow();
        Wrapped(win.AddText(Shorten(r.description, 300), 13), PANEL_W);
    }
    win.NewRow();
    @placeButton = win.AddButton("place it");
    Primary(placeButton);
    // someone else's prefab is only placed, deleted from this PC or updated from the store: its name, details and
    // pieces are theirs
    bool mine = Library::Mine(r) || r.source == Library::LOCAL;
    @replaceButton = null;
    @editButton = null;
    if (mine)
    {
        win.NewRow();
        @replaceButton = win.AddButton("replace with the selection");
        Secondary(replaceButton);
        win.NewRow();
        @editButton = win.AddButton("edit name, description and tags");
        Secondary(editButton);
    }
    @pictureButton = null;
    if (mine)
    {
        win.NewRow();
        @pictureButton = win.AddButton(pictureStep != 0 ? "taking the picture..." : (r.thumb == "" ? "use this view as its picture" : "new picture from this view"));
        Secondary(pictureButton);
        win.NewRow();
        Muted(Wrapped(win.AddText("frame it in the editor's view first: the picture is the middle of the view, without the panels", 12), PANEL_W));
    }
    @publishButton = null;
    @unpublishButton = null;
    @storeButton2 = null;
    if (r.slug == "" && mine)
    {
        win.NewRow();
        @publishButton = win.AddButton("publish to the store");
        Blue(publishButton);
    }
    else if (r.slug != "" && Library::CanPublishVersion(r))
    {
        win.NewRow();
        @publishButton = win.AddButton("publish this version");
        Blue(publishButton);
    }
    if (r.slug != "")
    {
        win.NewRow();
        @storeButton2 = win.AddButton(r.storeUpdated != "" ? "get the update in the store" : "see it in the store");
        Secondary(storeButton2);
    }
    if (r.versions > 0)
    {
        win.NewRow();
        Muted(win.AddText("older versions on this PC", 13));
        win.NewRow();
        for (int v = r.versions; v >= 1 && v > r.versions - 4; v--)
        {
            UI::Button@ b = win.AddButton("put back v" + v);
            Secondary(b);
            putBackButtons.insertLast(b);
        }
    }
    win.NewRow();
    @deleteButton = win.AddButton("delete from this PC");
    Danger(deleteButton);
    if (r.slug != "" && Library::Mine(r))
    {
        win.NewRow();
        @unpublishButton = win.AddButton("delete from the store");
        Danger(unpublishButton);
    }
}

void UpdateDetail()
{
    Library::Rec@ r = shown;
    if (r is null || Library::recs.findByRef(r) < 0)
    {
        Show(listView);
        return;
    }
    int count;
    string problem = SelectionProblem(count);
    if (replaceButton !is null)
        replaceButton.label = confirmReplace ? "click again to replace (old one kept)" : "replace with the selection (" + count + ")";
    if (backButton.Clicked())
    {
        Show(listView);
        return;
    }
    if (placeButton.Clicked())
        PlaceRec(r);
    if (replaceButton !is null && replaceButton.Clicked())
    {
        if (problem != "")
            Jobs::Say(problem, true);
        else if (!confirmReplace)
            confirmReplace = true;
        else
        {
            confirmReplace = false;
            string failed = Library::ReplaceWithSelection(r);
            Jobs::Say(failed == "" ? "“" + r.name + "” is the selection now; v" + r.versions + " is the old one" : failed, failed != "");
            RebuildDetail();
        }
    }
    if (editButton !is null && editButton.Clicked())
        OpenForm(r);
    if (pictureButton !is null && pictureButton.Clicked() && pictureStep == 0)
    {
        StartPicture(r, false);
        pictureButton.label = "taking the picture...";
    }
    if (publishButton !is null && publishButton.Clicked())
    {
        Jobs::Start(r.slug == "" ? Jobs::PUBLISH : Jobs::UPDATE, r);
        return;
    }
    if (storeButton2 !is null && storeButton2.Clicked())
        Store::OpenSearching(r.name);
    for (uint i = 0; i < putBackButtons.length(); i++)
        if (putBackButtons[i].Clicked())
        {
            string failed = Library::PutBack(r, r.versions - int(i));
            Jobs::Say(failed == "" ? "put back; what was there is v" + r.versions : failed, failed != "");
            RebuildDetail();
            return;
        }
    if (deleteButton.Clicked())
    {
        if (!confirmDelete)
        {
            confirmDelete = true;
            deleteButton.label = "click again: delete from this PC";
        }
        else
        {
            string name = r.name, failed = Library::Forget(r);
            Jobs::Say(failed == "" ? "deleted “" + name + "” from this PC" + (r.slug != "" ? " (the store still has it)" : "") : failed, failed != "");
            Show(listView);
            shownChanges = -1;
            return;
        }
    }
    if (unpublishButton !is null && unpublishButton.Clicked())
    {
        if (!confirmUnpublish)
        {
            confirmUnpublish = true;
            unpublishButton.label = "click again: delete from the store";
        }
        else
            Jobs::Start(Jobs::UNPUBLISH, r);
    }
}

// A picture of the editor's view for `r`: the selection let go first (its highlight and gizmo would be in it) and
// selected again after.
void StartPicture(Library::Rec@ r, bool quiet)
{
    if (pictureStep != 0)
        return;
    @pictureOf = r;
    pictureQuiet = quiet;
    pictureSelection = Editor::Selection();
    Editor::Select(array<int>());
    pictureStep = 1;
    pictureAt = Host::Time() + 0.15;
}

// The picture's steps (see pictureStep): its file in the plugin's cache, a new name each time (a window keeps the
// picture it loaded for a file's name).
void UpdatePicture()
{
    if (pictureStep == 1 && Host::Time() >= pictureAt)
    {
        string name = "own-" + SafeName(pictureOf.file) + "-" + int(Host::Time() * 1000);
        if (Screen::Capture(name))
            pictureStep = 2;
        else
        {
            pictureStep = 0;
            Editor::Select(pictureSelection);
            Jobs::Say("couldn't take the picture: " + Screen::CaptureState(), true);
            shownChanges = -1;
        }
    }
    else if (pictureStep == 2)
    {
        string state = Screen::CaptureState();
        if (state == "pending")
            return;
        pictureStep = 0;
        if (pictureSelection.length() > 0)
            Editor::Select(pictureSelection);
        if (state.findFirst("done: ") == 0 && Library::recs.findByRef(pictureOf) >= 0)
        {
            pictureOf.thumb = state.substr(6);
            Library::Save(pictureOf);
            if (!pictureQuiet)
                Jobs::Say("“" + Shorten(pictureOf.name, 24) + "” has its picture", false);
        }
        else
            Jobs::Say("couldn't take the picture: " + state, true);
        Jobs::changes++;
    }
}

string SafeName(const string &in text)
{
    string res;
    for (uint i = 0; i < text.length() && res.length() < 40; i++)
    {
        uint8 c = text[i];
        res += (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 ? text.substr(i, 1) : "_";
    }
    return res == "" ? "prefab" : res;
}

void PlaceRec(Library::Rec@ r)
{
    int count;
    string failed = Place::Place(r.file, count);
    if (failed != "")
        Jobs::Say(failed, true);
    else if (Jobs::messageBad)
        Jobs::Say("", false);           // an old problem is over once a prefab is placed
}

// Which sections of the list are folded (kept in storage).
bool Folded(int section) { return Storage::Get("tab.folded", "").findFirst("|" + section + "|") >= 0; }

void SetFolded(int section, bool on)
{
    string all = Replace(Storage::Get("tab.folded", ""), "|" + section + "|", "");
    if (on)
        all += "|" + section + "|";
    Storage::Set("tab.folded", all);
}

// --- each frame -------------------------------------------------------------------------------------------------------

void Update()
{
    if (!Editor::IsOpen())
        return;
    if (Host::Time() > nextReconcile)
    {
        nextReconcile = Host::Time() + 2;
        string files = Join(Prefabs::List(), "|");
        if (files != shownFiles)
        {
            shownFiles = files;
            Library::Reconcile();
            listDirty = true;
            shownChanges = -1;
        }
    }
    UpdatePicture();
    statusText.text = Jobs::message;
    statusText.visible = Jobs::message != "" && (view != listView || Jobs::messageBad);
    if (Jobs::messageBad)
        statusText.SetColor(BAD_R, BAD_G, BAD_B, 1);
    else
        statusText.SetColor(MUTED_R, MUTED_G, MUTED_B, 1);
    if (view == listView)
    {
        if (listDirty || filterInput.typed != shownFilter || Jobs::changes != listChanges)
            RebuildList();
        int count;
        string problem = SelectionProblem(count);
        if (createButton.Clicked())
        {
            if (problem != "")
                Jobs::Say(problem, true);
            else
                OpenForm(null);
        }
        if (storeButton.Clicked())
            Store::Open();
        for (uint i = 0; i < foldButtons.length(); i++)
            if (foldButtons[i].Clicked())
            {
                SetFolded(int(i), !Folded(int(i)));
                listDirty = true;
            }
        for (uint i = 0; i < rowRecs.length(); i++)
        {
            if (moreButtons[i].Clicked())
            {
                OpenDetail(rowRecs[i]);
                return;
            }
            if (win.CardClicked(rowCards[i]))
                PlaceRec(rowRecs[i]);
        }
    }
    else if (view == formView)
        UpdateForm();
    else if (view == detailView)
    {
        if (Jobs::changes != shownChanges)
        {
            shownChanges = Jobs::changes;
            if (Library::recs.findByRef(shown) >= 0)
                RebuildDetail();
        }
        UpdateDetail();
    }
}

}  // namespace Tab
