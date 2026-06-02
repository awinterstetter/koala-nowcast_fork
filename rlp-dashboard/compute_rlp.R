library(coalitions)
library(dplyr)
library(purrr)
library(tidyr)
library(jsonlite)

cat("Fetching RLP polls from wahlrecht.de...\n")
rp <- get_surveys_rp()
cat("Pollsters found:", paste(rp$pollster, collapse = ", "), "\n")

# Pool surveys from the last 14 days across all pollsters
cat("Pooling surveys...\n")
pooled_flat <- pool_surveys(rp, pollsters = unique(rp$pollster), period = 14)

# Reconstruct nested format required by draw_from_posterior / get_seats
pooled <- pooled_flat %>%
  nest(survey = c(party, percent, votes)) %>%
  slice(1)

cat("Pooled survey date:", format(pooled$date), "\n")
cat("N respondents (effective):", round(pooled$respondents), "\n")
cat("Party shares:\n")
print(pooled$survey[[1]])

# Define relevant coalitions for RLP 2026
coalitions_rlp <- list(
  "cdu_spd"        = c("cdu", "spd"),
  "cdu_greens"     = c("cdu", "greens"),
  "cdu_fdp"        = c("cdu", "fdp"),
  "cdu_afd"        = c("cdu", "afd"),
  "cdu_fw"         = c("cdu", "fw"),
  "spd_greens"     = c("spd", "greens"),
  "spd_greens_fdp" = c("spd", "greens", "fdp"),
  "cdu_spd_greens" = c("cdu", "spd", "greens"),
  "cdu_spd_fw"     = c("cdu", "spd", "fw"),
  "cdu_greens_fdp" = c("cdu", "greens", "fdp")
)

coalition_labels <- c(
  "cdu_spd"        = "CDU + SPD",
  "cdu_greens"     = "CDU + Grüne",
  "cdu_fdp"        = "CDU + FDP",
  "cdu_afd"        = "CDU + AfD",
  "cdu_fw"         = "CDU + Freie Wähler",
  "spd_greens"     = "SPD + Grüne",
  "spd_greens_fdp" = "SPD + Grüne + FDP",
  "cdu_spd_greens" = "CDU + SPD + Grüne",
  "cdu_spd_fw"     = "CDU + SPD + Freie Wähler",
  "cdu_greens_fdp" = "CDU + Grüne + FDP (Jamaica)"
)

nsim <- 100000
cat(sprintf("\nRunning %s Monte Carlo simulations...\n", format(nsim, big.mark = ",")))

# RLP Landtag has 101 seats (minimum), majority = 51
n_seats_rlp  <- 101L
seats_majority_rlp <- 51L

draws <- draw_from_posterior(pooled$survey[[1]], nsim = nsim)
seats <- get_seats(draws, pooled$survey[[1]], n_seats = n_seats_rlp)

cat("Computing coalition probabilities...\n")
majority_df <- have_majority(seats, coalitions = coalitions_rlp,
                             seats_majority = seats_majority_rlp)
# have_majority sorts party names alphabetically within coalitions —
# use the actual column names from majority_df as keys
coalition_keys <- as.list(names(majority_df))

# Build label lookup from sorted keys -> human labels
make_label <- function(key) {
  parties <- strsplit(key, "_")[[1]]
  labels <- c(cdu = "CDU", spd = "SPD", greens = "Grüne", fdp = "FDP",
               afd = "AfD", fw = "Freie Wähler", left = "Linke")
  paste(labels[parties], collapse = " + ")
}
label_lookup <- setNames(sapply(coalition_keys, make_label), coalition_keys)

probs <- calculate_probs(majority_df, coalition_keys, exclude_superior = FALSE) %>%
  mutate(
    label       = label_lookup[coalition],
    probability = round(probability / 100, 4)
  ) %>%
  arrange(desc(probability))

cat("\nCoalition probabilities:\n")
print(probs)

# Seat distribution summary
seats_summary <- seats %>%
  filter(party != "others") %>%
  group_by(party) %>%
  summarise(
    seats_mean   = round(mean(seats), 1),
    seats_median = as.integer(median(seats)),
    seats_q05    = as.integer(quantile(seats, 0.05)),
    seats_q95    = as.integer(quantile(seats, 0.95)),
    .groups = "drop"
  ) %>%
  arrange(desc(seats_median))

cat("\nSeat distribution:\n")
print(seats_summary)

# Per-pollster latest shares
per_pollster <- rp %>%
  mutate(latest = map(surveys, ~ slice(.x, 1))) %>%
  unnest(latest) %>%
  unnest(survey) %>%
  filter(party != "others") %>%
  select(pollster, date, party, percent) %>%
  arrange(pollster, desc(percent))

# Party hurdle probabilities (prob of clearing 5%)
# draws contains proportions (0-1), so threshold is 0.05
hurdle_threshold <- 0.05
hurdle_probs <- as.data.frame(draws) %>%
  summarise(across(everything(), ~ mean(.x >= hurdle_threshold))) %>%
  tidyr::pivot_longer(everything(), names_to = "party", values_to = "prob_above_hurdle") %>%
  filter(party != "others") %>%
  mutate(prob_above_hurdle = round(prob_above_hurdle, 4)) %>%
  arrange(desc(prob_above_hurdle))

cat("\nHurdle probabilities:\n")
print(hurdle_probs)

# Save all JSON outputs
cat("\nSaving JSON files to data/...\n")
ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

write_json(
  list(
    updated    = ts,
    election   = "Rheinland-Pfalz Landtagswahl 2026",
    date       = format(pooled$date),
    coalitions = probs
  ),
  "data/coalition_probabilities.json", pretty = TRUE, auto_unbox = TRUE
)

write_json(
  list(
    updated      = ts,
    party_shares = pooled$survey[[1]] %>% filter(party != "others") %>% arrange(desc(percent))
  ),
  "data/party_shares.json", pretty = TRUE, auto_unbox = TRUE
)

write_json(
  list(updated = ts, seats = seats_summary),
  "data/seat_distribution.json", pretty = TRUE, auto_unbox = TRUE
)

write_json(
  list(updated = ts, hurdle = hurdle_probs),
  "data/hurdle_probabilities.json", pretty = TRUE, auto_unbox = TRUE
)

write_json(
  list(updated = ts, per_pollster = per_pollster),
  "data/per_pollster.json", pretty = TRUE, auto_unbox = TRUE
)

# Seat draws sample (first 1000 sims for frontend histogram)
draws_sample <- seats %>%
  filter(party != "others", sim <= 1000)

write_json(draws_sample, "data/seat_draws.json", pretty = FALSE, auto_unbox = TRUE)

cat("Done!\n")
