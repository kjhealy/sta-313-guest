## --------------------------------------------------------------------------------------------------------------------
library(tidyverse)
library(janitor)

## https://kjhealy.github.io/socviz
library(socviz)

###-------------------------------------------------
### Not needed to draw the graphs
library(showtext)
showtext_auto()

library(myriad)
import_myriad_semi_ttf()

theme_set(theme_myriad_new())
###-------------------------------------------------


library(patchwork)



## --------------------------------------------------------------------------------------------------------------------
## https://kjhealy.github.io/covdata
library(covdata)

### stmf graph

## --------------------------------------------------------------------------------------------------------------------

rate_rank <- stmf %>%
  filter(sex == "b", year > 2014 & year < 2020) %>%
  group_by(country_code) %>%
  summarize(mean_rate = mean(rate_total, na.rm = TRUE)) %>%
  mutate(rate_rank = rank(mean_rate))


rate_max_rank <- stmf %>%
  filter(sex == "b", year == 2020) %>%
  group_by(country_code) %>%
  summarize(covid_max = max(rate_total, na.rm = TRUE)) %>%
  mutate(covid_max_rank = rank(covid_max))

out <- stmf %>%
  filter(sex == "b", year > 2014, year < 2021,
         country_code %in% c("AUT", "BEL", "CHE", "DEUTNP", "DNK", "ESP", "FIN",
                             "FRATNP", "GBR_SCO", "GBRTENW", "GRC", "HUN",
                             "ITA", "LUX", "POL", "NLD", "NOR", "PRT", "SWE", "USA")) %>%
  filter(!(year == 2020 & week > 53)) %>%
  group_by(cname, year, week) %>%
  mutate(yr_ind = year %in% 2020) %>%
  slice(1) %>%
  left_join(rate_rank, by = "country_code") %>%
  left_join(rate_max_rank, by = "country_code") %>%
  ggplot(aes(x = week, y = rate_total, color = yr_ind, group = year)) +
  scale_color_manual(values = c("gray70", "firebrick"), labels = c("2015-2019", "2020")) +
  scale_x_continuous(limits = c(1, 52),
                     breaks = c(1, seq(10, 50, 10)),
                     labels = as.character(c(1, seq(10, 50, 10)))) +
  facet_wrap(~ reorder(cname, -rate_rank, na.rm = TRUE), ncol = 5) +
  geom_line(size = 0.9) +
  guides(color = guide_legend(override.aes = list(size = 3))) +
  labs(x = "Week of the Year",
       y = "Total Death Rate",
       color = "Year",
       title = "Overall Weekly Death Rates",
       subtitle = "Comparing 2020 with 2015-2019 across selected countries. Countries are shown top left to bottom right ordered from highest to lowest average mortality rate in 2015-2019.",
       caption = "Graph: @kjhealy. Data: Human Mortality Database, mortality.org") +
  theme(legend.position = "top",
        plot.title = element_text(size = rel(2.6)),
        plot.subtitle = element_text(size = rel(1.25)),
        strip.text = element_text(size = rel(1.4), hjust = 0),
        legend.text = element_text(size = rel(1.1)),
        legend.title = element_text(size = rel(1.1)))


ggsave("figures/national_mortality_rates-wide.pdf", out, height = 10, width = 16)


### US States and causes of death

states <- nchs_wdc %>%
  select(jurisdiction) %>%
  unique()

states <- states %>%
  mutate(fname = paste0(here::here("figures", tolower(jurisdiction)), "_patch"),
         fname = stringr::str_replace_all(fname, " ", "_"))


start_week <- 1
end_week <- 53

dat <- nchs_wdc %>%
  filter(year > 2014, year < 2021) %>%
  mutate(month_label = lubridate::month(week_ending_date, label = TRUE))

average_deaths <- nchs_wdc %>%
  filter(year %in% c(2015:2019)) %>%
  group_by(jurisdiction, week, cause) %>%
  summarize(average_wk_deaths = mean(n, na.rm = TRUE))

df <- left_join(dat, average_deaths) %>%
  select(everything(), n, average_wk_deaths) %>%
  mutate(n_diff = n - average_wk_deaths,
         pct_diff = (n_diff / n)*100) %>%
  filter(cause %nin% c("Natural Causes", "Other"))


## Choose how many red-line wks
nwks <- 53

season_label <- tibble(wk_num = lubridate::epiweek(as.Date(c("2020-03-01",
                                                             "2020-06-01",
                                                             "2020-09-01",
                                                             "2020-12-01"))),
                       season_lab = c("Spring", "Summer", "Autumn", "Winter"))

season_label

month_label <- tibble(wk_num = lubridate::epiweek(lubridate::ymd("2020-01-15") + months(0:11)),
                      month_lab = as.character(lubridate::month(lubridate::ymd("2020-01-15") +
                                                                  months(0:11), label = TRUE)))

month_label

order_panels <- function(st = state, ...) {
  df %>%
    filter(year < 2021,
           jurisdiction %in% st, cause != "All Cause") %>%
    group_by(cause) %>%
    summarize(deaths = sum(n, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(cause_rank = rank(-deaths),
           o = order(cause_rank),
           cause_ord = factor(cause, levels = cause[o], ordered = TRUE)) %>%
    select(cause, cause_ord)
}

patch_state_count <- function(state) {

  out <- df %>%
    filter(year < 2021, jurisdiction %in% state, cause == "All Cause") %>%
    group_by(year, week) %>%
    mutate(yr_ind = year %in% 2020) %>%
    filter(!(year == 2020 & week > nwks)) %>%
    ggplot(aes(x = week, y = n, color = yr_ind, group = year)) +
    geom_line(size = 0.9) +
    scale_color_manual(values = c("gray70", "firebrick"), labels = c("2015-2019", "2020")) +
    scale_x_continuous(breaks = month_label$wk_num, labels = month_label$month_lab) +
    scale_y_continuous(labels = scales::comma) +
    labs(x = NULL,
         y = "Total Deaths",
         color = "Years",
         title = "Weekly recorded deaths from all causes",
         subtitle = "Raw Counts. Provisional Data.")

  out

}

patch_state_cause <- function(state, nc = 2) {

  panel_ordering <- order_panels(st = state)

  out <- df %>%
    filter(year < 2021,
           jurisdiction == state,
           cause %nin% c("All Cause", "COVID-19 Multiple cause", "COVID-19 Underlying")) %>%
    group_by(cause, year, week) %>%
    summarize(deaths = sum(n, na.rm = TRUE), .groups = "drop") %>%
    mutate(yr_ind = year %in% 2020) %>%
    filter(!(year == 2020 & week > nwks)) %>%
    left_join(panel_ordering, by = "cause") %>%
    ggplot(aes(x = week, y = deaths, color = yr_ind)) +
    geom_line(size = 0.9, mapping = aes(group = year)) +
    scale_color_manual(values = c("gray70", "firebrick"), labels = c("2015-2019", "2020")) +
    scale_x_continuous(breaks = c(1, 10, 20, 30, 40, 50), labels = as.character(c(1, 10, 20, 30, 40, 50))) +
    scale_y_continuous(labels = scales::comma) +
    facet_wrap(~ cause_ord, ncol = nc, labeller = label_wrap_gen(25)) +
    labs(x = "Week of the Year",
         y = "Total Deaths",
         color = "Years",
         title = "Weekly deaths from selected causes",
         subtitle = "Panels ordered by number of deaths. Raw Counts.")

  out
}

patch_state_percent <- function(state, nc = 2){

  panel_ordering <- order_panels(st = state)

  out <- df %>%
    filter(year < 2021) %>%
    filter(jurisdiction %in% state,
           year == 2020,
           cause %nin% c("All Cause", "COVID-19 Multiple cause",
                         "COVID-19 Underlying"), !is.na(pct_diff)) %>%
    group_by(week) %>%
    filter(!(week > nwks)) %>%
    mutate(ov_un = pct_diff > 0) %>%
    left_join(panel_ordering, by = "cause") %>%
    ggplot(aes(x = week, y = pct_diff/100, fill = ov_un)) +
    geom_col() +
    scale_x_continuous(breaks = c(1, seq(10, nwks, 10)), labels = as.character(c(1, seq(10, nwks, 10)))) +
    scale_y_continuous(labels = scales::percent) +
    scale_fill_manual(values = c("gray40", "firebrick")) +
    guides(fill = "none") +
    facet_wrap(~ cause_ord, ncol = nc, labeller = label_wrap_gen(25)) +
    labs(x = "Week of the Year",
         y = "Percent",
         title = "Percent difference from 2015-2019 average")

  out
}

patch_state_covid <- function(state) {

  out <- df %>%
    filter(year < 2021) %>%
    filter(jurisdiction %in% state, cause %in% c("COVID-19 Multiple cause")) %>%
    group_by(year, week) %>%
    mutate(yr_ind = year %in% 2020) %>%
    filter(year == 2020) %>%
    ggplot(aes(x = week, y = n, group = year)) +
    geom_col(fill = "gray30") +
    scale_x_continuous(breaks = c(1, 10, 20, 30, 40, 50),
                       labels = as.character(c(1, 10, 20, 30, 40, 50)),
                       limits = c(1, 52)) +
    scale_y_continuous(labels = scales::comma) +
    labs(x = "Week of the Year",
         y = "Total Deaths",
         color = "Years",
         subtitle = "Raw counts.",
         title = "Weekly deaths recorded as COVID-19 (Multiple cause)")

  out

}

make_patchplot <- function(state){

  if(state == "New York")  {
    state_title <- paste(state, "(Excluding New York City)")
  } else
  {
    state_title <- state
  }

  timestamp <-  lubridate::stamp("March 1, 1999", "%B %d, %Y")(lubridate::ymd(Sys.Date()))


  (patch_state_count(state) + theme(plot.margin = unit(c(5,0,0,0), "pt"))) /
    patch_state_covid(state) /
    (patch_state_cause(state) + (patch_state_percent(state))) +
    plot_layout(heights = c(2, 0.5, 4), guides = 'collect') +
    plot_annotation(
      title = state_title,
      caption = paste0("Graph: @kjhealy Data: CDC. This graph was made on ", timestamp, "."),
      theme = theme(plot.title = element_text(size = rel(2), hjust = 0, face = "plain")))
}

out_patch <- states %>%
  mutate(patch_plot = map(jurisdiction, make_patchplot))

walk2(paste0(out_patch$fname, ".png"),
      out_patch$patch_plot, ggsave, height = 16, width = 9, dpi = 200)

