/// App spacing constants following 8pt grid system
class AppSpacing {
  // Base unit (8pt)
  static const double unit = 8.0;

  // Common spacing values
  static const double xs = unit * 0.5;  // 4pt
  static const double sm = unit * 1;    // 8pt
  static const double md = unit * 2;    // 16pt
  static const double lg = unit * 3;    // 24pt
  static const double xl = unit * 4;    // 32pt
  static const double xxl = unit * 5;   // 40pt
  static const double xxxl = unit * 6;  // 48pt

  // Named spacing for specific use cases
  static const double padding = md;           // Default padding
  static const double paddingSmall = sm;      // Small padding
  static const double paddingLarge = lg;      // Large padding

  static const double margin = md;            // Default margin
  static const double marginSmall = sm;       // Small margin
  static const double marginLarge = lg;       // Large margin

  static const double cardPadding = md;       // Card internal padding
  static const double cardMargin = sm;        // Card external margin

  static const double listItemPadding = md;   // List item padding
  static const double listItemSpacing = sm;   // Space between list items

  static const double buttonPaddingVertical = md;      // Button vertical padding
  static const double buttonPaddingHorizontal = lg;    // Button horizontal padding

  static const double iconSize = lg;          // Default icon size (24pt)
  static const double iconSizeSmall = md;     // Small icon size (16pt)
  static const double iconSizeLarge = xl;     // Large icon size (32pt)

  static const double borderRadius = sm;      // Default border radius
  static const double borderRadiusSmall = xs; // Small border radius
  static const double borderRadiusLarge = md; // Large border radius
  static const double borderRadiusCard = 12.0;  // Card border radius

  static const double dividerThickness = 1.0; // Divider thickness
  static const double borderWidth = 1.0;      // Border width
}
