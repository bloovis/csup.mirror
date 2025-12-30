# Lines of text in any mode derived from ScrollMode are an array of either:
# - a String, which is displayed using a default color
# - an Array of Widgets
# A Widget is a String annotated with a Symbol representing its color.
# A single line in the display can be made up of multiple Widgets, theoretically
# allowing every character on the line to have its own color.

module Redwood

# A `Widget` is a tuple containg a string and the color that
# should be applied to that string.
alias Widget = Tuple(Symbol, String)	# {color, text}

# A line of text can be an array of `Widget` objects.  This
# is used for text lines that contain strings of diferent colors.
alias WidgetArray = Array(Widget)

# A line of text is either a string with a single default color,
# or an array of `Widget` objects, each of which is a string
# with its own color.
alias Text = WidgetArray | String

# Lines of text as represented in all Modes derived from `ScrollMode`.
# Each line is either a string with a single default color,
# or an array of `Widget` objects, each of which is a string
# with its own color.
alias TextLines = Array(Text)

end
