///|
/// Scenarios transform the household ledger, never the purchase financing terms.
pub(all) enum Stress {
  Baseline
  Delay(String, Int, Int)
  IncomeDrop(String, Int, Int, Int)
  ExtraExpense(Int, Int64)
} derive(Debug)

///|
pub extend Stress with Debug::{to_repr}

///|
pub fn stress_name(stress : Stress) -> String {
  match stress {
    Baseline => "baseline"
    Delay(_, _, _) => "income_delay"
    IncomeDrop(_, _, _, _) => "income_drop"
    ExtraExpense(_, _) => "extra_expense"
  }
}

///|
pub fn apply_stress(
  entries : Array[Entry],
  stress : Stress,
) -> Array[Entry] raise InputError {
  let result : Array[Entry] = []
  let mut matched = false
  match stress {
    Baseline => entries.copy()
    Delay(label, day, delta) => {
      if delta < 1 || delta > 365 {
        raise Invalid("income delay outside 1..365 days")
      }
      for e in entries {
        if e.label == label && e.day == day && e.cents > 0L {
          ignore(date_from_serial(e.day + delta))
          result.push({ ..e, day: e.day + delta, })
          matched = true
        } else {
          result.push(e)
        }
      }
      if !matched {
        raise Invalid("delayed income occurrence not found")
      }
      result
    }
    IncomeDrop(label, first, last, retained_percent) => {
      if first > last || retained_percent < 0 || retained_percent > 100 {
        raise Invalid("invalid income drop interval or retained percent")
      }
      for e in entries {
        if e.label == label && e.day >= first && e.day <= last && e.cents > 0L {
          validate_money(e.cents, nonnegative=true)
          // Half up rounding to one cent; multiplication is bounded by validation.
          result.push({
            ..e,
            cents: (e.cents * retained_percent.to_int64() + 50L) / 100L,
          })
          matched = true
        } else {
          result.push(e)
        }
      }
      if !matched {
        raise Invalid("income drop has no matching income")
      }
      result
    }
    ExtraExpense(day, cents) => {
      validate_money(cents, nonnegative=true)
      ignore(date_from_serial(day))
      result.append(entries)
      result.push({ day, label: "unexpected expense", cents: -cents, })
      result
    }
  }
}
