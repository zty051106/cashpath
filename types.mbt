///|
/// Input validation errors are part of the public API.
pub suberror InputError {
  Invalid(String)
} derive(Debug)

///|
/// All ledger amounts are integer cents. Positive entries are inflows.
pub(all) struct Entry {
  day : Int
  label : String
  cents : Int64
} derive(Debug, Eq)

///|
pub extend InputError with Debug::{to_repr}

///|
pub extend Entry with Debug::{to_repr}

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Date with Debug::{to_repr}

///|
pub extend Date with Eq::{equal, not_equal}

///|
pub extend Path with Debug::{to_repr}

///|
pub extend Plan with Debug::{to_repr}

///|
pub extend Plan with Eq::{equal, not_equal}

///|
pub extend Candidate with Debug::{to_repr}

///|
pub(all) struct Date {
  year : Int
  month : Int
  day : Int
} derive(Debug, Eq)

///|
/// Result of walking every event (including intra-day outflow minima).
pub(all) struct Path {
  ending_cents : Int64
  minimum_cents : Int64
  minimum_day : Int
  first_breach : Entry?
  peak_shortfall_cents : Int64
  feasible : Bool
  events : Array[Entry]
  balances : Array[Int64]
} derive(Debug)

///|
/// Explicit plans contain all fees in the down payment and monthly payment.
pub(all) struct Plan {
  id : String
  cash_price_cents : Int64
  down_cents : Int64
  monthly_cents : Int64
  months : Int
} derive(Debug, Eq)

///|
pub(all) struct Candidate {
  id : String
  delay_days : Int
  total_cents : Int64
  present_value_cents : Double
  worst_path : Path
  scenarios : Array[(String, Path)]
} derive(Debug)

///|
/// Initial balance and event magnitudes are bounded to avoid Int64 overflow.
pub fn validate_money(
  cents : Int64,
  nonnegative~ : Bool,
) -> Unit raise InputError {
  if cents < -1000000000000L ||
    cents > 1000000000000L ||
    (nonnegative && cents < 0L) {
    raise Invalid("amount outside supported range (up to 10 billion CNY)")
  }
}
