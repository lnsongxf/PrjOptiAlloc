ffy_opt_ghthm_dk <- function() {
#' ghthm = graph theme, support theme files
#'
#' @description
#' Theme from Dominik Koch found on luisdva.github.io
#'
#' @return ggplot theme
#' @author Dominik Koch, \url{https://luisdva.github.io/rstats/dog-bump-chart/}
#' @references
#' \url{https://luisdva.github.io/rstats/dog-bump-chart/}
#' @export
#' @import ggplot2

# Colors
color.background = "white"
color.text = "#22211d"

# Begin construction of chart
theme_bw(base_size=15) +

  # Format background colors
  theme(panel.background = element_rect(fill=color.background, color=color.background)) +
  theme(plot.background  = element_rect(fill=color.background, color=color.background)) +
  theme(panel.border     = element_rect(color=color.background)) +
  theme(strip.background = element_rect(fill=color.background, color=color.background)) +

  # Format the grid
  theme(panel.grid.major.y = element_blank()) +
  theme(panel.grid.minor.y = element_blank()) +
  theme(axis.ticks       = element_blank()) +

  # Format the legend
  theme(legend.position = "none") +

  # Format title and axis labels
  theme(plot.title       = element_text(color=color.text, size=20, face = "bold")) +
  theme(axis.title.x     = element_text(size=14, color="black", face = "bold")) +
  theme(axis.title.y     = element_text(size=14, color="black", face = "bold", vjust=1.25)) +
  theme(axis.text.x      = element_text(size=10, vjust=0.5, hjust=0.5, color = color.text)) +
  theme(axis.text.y      = element_text(size=10, color = color.text)) +
  theme(strip.text       = element_text(face = "bold")) +

  # Plot margins
  theme(plot.margin = unit(c(0.35, 0.2, 0.3, 0.35), "cm"))

}
