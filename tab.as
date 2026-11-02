// The prefabs tab in the editor's left panel (Window.DockInEditorTab: a fifth button after the game's four):
//   prefabs                                     7
//   [ create from selection (12) ]
//   [ open the prefab store ]
//   [ filter my prefabs             ]
//   local only 2
//     [pic] loop gate          [place] [more]
//           18 pieces · 6.2 × 3 × 4 m
//           not published
//   published by you 2 ...   downloaded 3 ...
// "more" opens a prefab's page (place, replace with the selection, edit, publish, versions, delete); "create" opens the
// form (name, description, tags, the selection checked against the game's rules).
// Widths are layout units: the tab's panel has about 330 for its content, a card's text beside its picture 222.
const float PANEL_W = 330, CARD_TEXT_W = 222;

namespace Tab
{

UI::Window@ win;
int listView, formView, detailView;
UI::Text@ countText, statusText;
UI::Button@ createButton, storeButton;
UI::TextInput@ filterInput;

// the list
array<Library::Rec@> rowRecs;
array<UI::Button@> placeButtons, moreButtons;
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
UI::Button@ backButton, placeButton, replaceButton, editButton, publishButton, unpublishButton, deleteButton, storeButton2;
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
    @countText = win.AddText("", 15);
    Muted(countText);
    win.NewRow();
    @createButton = win.AddButton("create from selection");
    Primary(createButton);
    win.NewRow();
    @storeButton = win.AddButton("open the prefab store");
    Secondary(storeButton);
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
    countText.visible = list;
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
    placeButtons.resize(0);
    moreButtons.resize(0);
    countText.text = Library::recs.length() + " on this PC";
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
        win.NewRow();
        win.AddText(titles[s], 19);
        Muted(win.AddText("" + rows.length(), 14));
        if (rows.length() == 0)
        {
            win.NewRow();
            Muted(win.AddText(s == 0 ? "none: select pieces and create one" : (s == 1 ? "none yet" : "none: find some in the store"), 13));
        }
        for (uint i = 0; i < rows.length(); i++)
        {
            Library::Rec@ r = rows[i];
            win.StartCard();
            win.AddImage(ThumbOf(r.thumb), 64, 40);
            Wrapped(win.AddText(Shorten(r.name, 40), 16), CARD_TEXT_W);
            win.NewRow();
            win.AddSpace(64);
            Muted(Wrapped(win.AddText(Meta(r), 12), CARD_TEXT_W));
            win.NewRow();
            win.AddSpace(64);
            float red, green, blue;
            string badge = Badge(r, red, green, blue);
            Wrapped(win.AddText(badge, 12), CARD_TEXT_W).SetColor(red, green, blue, 1);
            win.NewRow();
            win.AddSpace(64);
            UI::Button@ place = win.AddButton("place");
            Primary(place);
            UI::Button@ more = win.AddButton("more");
            Secondary(more);
            win.EndCard();
            rowRecs.insertLast(r);
            placeButtons.insertLast(place);
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

void PlaceRec(Library::Rec@ r)
{
    int count;
    string failed = Place::Place(r.file, count);
    Jobs::Say(failed == "" ? "placed “" + Shorten(r.name, 18) + "” (" + count + ")" : failed, failed != "");
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
    statusText.text = Jobs::message;
    statusText.visible = Jobs::message != "";
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
        createButton.label = count > 0 ? "create from selection (" + count + ")" : "create from selection";
        if (createButton.Clicked())
        {
            if (problem != "")
                Jobs::Say(problem, true);
            else
                OpenForm(null);
        }
        if (storeButton.Clicked())
            Store::Open();
        for (uint i = 0; i < rowRecs.length(); i++)
        {
            if (placeButtons[i].Clicked())
                PlaceRec(rowRecs[i]);
            if (moreButtons[i].Clicked())
            {
                OpenDetail(rowRecs[i]);
                return;
            }
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
