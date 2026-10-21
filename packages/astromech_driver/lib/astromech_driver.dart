/// In-app half of astromech: VM service extensions that let the `astromech`
/// CLI (and the agents driving it) find, tap and read widgets of a debug build.
library;

export 'src/astromech.dart' show registerAstromech;
export 'src/home_navigator.dart' show HomeNavigator;
export 'src/widget_finder.dart' show FoundWidget, WidgetFinder, WidgetSelector;
