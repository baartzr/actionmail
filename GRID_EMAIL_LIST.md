# Grid-Style Email List Mockup

This document describes the grid-style desktop email list mockup that has been created to investigate an alternative to the traditional tile-style email list.

## Overview

The mockup demonstrates a full-screen, grid-based email view that is:
- **Full screen** - No side panels, maximum screen real estate for emails
- **Grid layout** - Emails displayed as cards in a responsive grid
- **Filter-first** - All filters visible and easily accessible at the top
- **Minimalist** - Clean, uncluttered design
- **Visual** - Colored flags provide visual interest and quick scanning
- **Action-focused** - Easy to view and manage actions

## Files Created

### 1. `lib/features/home/presentation/widgets/grid_email_list_mockup.dart`

The main mockup widget that implements the grid-style email list view.

**Key Features:**
- Full-screen layout with no side panels
- App bar with folder dropdown (no folder list sidebar)
- Filter bar showing all available filters as chips
- Responsive grid layout (3-6 columns based on screen width)
- Email cards with:
  - Colored flags on the left edge (red for overdue actions, orange for actions, blue for personal, purple for business, amber for starred, teal for attachments)
  - Sender name and email
  - Subject and snippet
  - Action indicators
  - Status icons (star, attachment, unread dot)
  - Date display

**Filter Options:**
- All
- Unread
- Starred
- Has Action
- Personal
- Business
- Attachments
- Overdue

### 2. `lib/features/home/presentation/screens/grid_email_list_demo.dart`

A demo screen that showcases the mockup with sample email data.

**Usage:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const GridEmailListDemo()),
);
```

## Design Principles

### 1. Full Screen, No Side Panels
- The entire screen is dedicated to viewing emails
- Folder selection is via the app bar dropdown (as requested)
- No folder tree or account list taking up space

### 2. Single View with All Filters
- Filter bar is always visible at the top
- All filters are shown as chips, making it easy to see what's active
- Filters can be toggled on/off with a single click

### 3. Grid Layout
- Emails are displayed as cards in a grid
- Responsive: 3-6 columns based on screen width
- Cards are taller than wide (aspect ratio 0.75) for better content display

### 4. Colored Flags
- Visual indicators on the left edge of each card
- Color coding:
  - **Red**: Overdue actions
  - **Orange**: Actions with dates
  - **Blue**: Personal emails
  - **Purple**: Business emails
  - **Amber**: Starred emails
  - **Teal**: Emails with attachments
- Provides quick visual scanning of email types

### 5. Minimalist Style
- Clean, uncluttered design
- Subtle borders and shadows
- Focus on content, not decoration
- Read/unread states are subtle (background color and border)

### 6. Action Management
- Action indicators are prominently displayed
- Overdue actions are highlighted in red
- Action status (complete/incomplete) is clearly shown
- Easy to see which emails require attention

## Integration Notes

### Moving Emails to Local Folders

The mockup currently shows the visual design. To add drag-and-drop functionality for moving emails to local folders:

1. Wrap email cards in `Draggable<MessageIndex>` widgets
2. Add a drop zone (e.g., a floating action button or menu) for local folders
3. Use `DragTarget<MessageIndex>` to accept drops
4. Call the existing `LocalFolderService` methods to move emails

Example integration:
```dart
Draggable<MessageIndex>(
  data: email,
  child: _EmailGridCard(...),
  // ... drag configuration
)
```

### Filtering

The mockup includes a filter bar, but you'll need to:
1. Connect filters to your email list provider
2. Implement the filtering logic based on email properties
3. Update the email list when filters change

### Folder Selection

The app bar includes a folder dropdown. This should:
1. Connect to your existing folder selection logic
2. Update the email list when folder changes
3. Show the current folder name

## Next Steps

1. **Review the mockup** - Navigate to `GridEmailListDemo` to see the design
2. **Gather feedback** - Determine if this style meets your requirements
3. **Integrate with existing code** - Connect the mockup to your email list provider
4. **Add drag-and-drop** - Implement moving emails to local folders
5. **Polish** - Refine colors, spacing, and interactions based on feedback

## Customization

The mockup is designed to be easily customizable:

- **Grid columns**: Adjust `crossAxisCount` calculation in `_buildEmailGrid`
- **Card aspect ratio**: Change `childAspectRatio` in `SliverGridDelegateWithFixedCrossAxisCount`
- **Flag colors**: Modify the color logic in `_EmailGridCard._build`
- **Filter options**: Add/remove filters in `_buildFilterBar`
- **Card styling**: Adjust padding, borders, and colors in `_EmailGridCard`

## Comparison with Current Design

| Feature | Current (Tile) | Mockup (Grid) |
|---------|---------------|---------------|
| Layout | Vertical list | Grid of cards |
| Side panels | Yes (folders, accounts) | No (full screen) |
| Filters | Hidden in menu | Always visible |
| Visual scanning | Text-heavy | Color-coded flags |
| Screen usage | ~60% for emails | ~100% for emails |
| Folder selection | Sidebar tree | App bar dropdown |
| Action visibility | Expandable | Always visible |

## Questions to Consider

1. Does the grid layout work well for your email volume?
2. Are the colored flags intuitive and useful?
3. Is the filter bar placement and design effective?
4. How should drag-and-drop to local folders work in this layout?
5. Should there be a way to switch between grid and list views?

