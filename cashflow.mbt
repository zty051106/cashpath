///|
/// Stable insertion sort preserves input order within the same sign/day.
/// Outflows execute before inflows, so same-day salary is not assumed available.
fn ordered(events : Array[Entry]) -> Array[Entry] {
  let result = events.copy()
  for i in 1..<result.length() {
    let current = result[i]
    let mut j = i
    while j > 0 &&
          (
            result[j - 1].day > current.day ||
            (
              result[j - 1].day == current.day &&
              result[j - 1].cents >= 0L &&
              current.cents < 0L
            )
          ) {
      result[j] = result[j - 1]
      j = j - 1
    }
    result[j] = current
  }
  result
}

///|
pub fn simulate(
  opening : Int64,
  reserve : Int64,
  start_day : Int,
  end_day : Int,
  entries : Array[Entry],
) -> Path raise InputError {
  validate_money(opening, nonnegative=true)
  validate_money(reserve, nonnegative=true)
  ignore(date_from_serial(start_day))
  ignore(date_from_serial(end_day))
  if end_day < start_day || entries.length() > 12000 {
    raise Invalid("invalid horizon or too many events")
  }
  for e in entries {
    validate_money(e.cents, nonnegative=false)
    if e.day < start_day || e.day > end_day {
      raise Invalid("event outside evaluation horizon")
    }
  }
  let events = ordered(entries)
  let balances : Array[Int64] = []
  let mut balance = opening
  let mut minimum = opening
  let mut minimum_day = start_day
  let mut breach : Entry? = if opening < reserve {
    Some({ day: start_day, label: "opening balance", cents: 0L, })
  } else {
    None
  }
  for event in events {
    balance = balance + event.cents
    balances.push(balance)
    if balance < minimum {
      minimum = balance
      minimum_day = event.day
    }
    if balance < reserve && breach is None {
      breach = Some(event)
    }
  }
  {
    ending_cents: balance,
    minimum_cents: minimum,
    minimum_day,
    first_breach: breach,
    peak_shortfall_cents: if minimum < reserve {
      reserve - minimum
    } else {
      0L
    },
    feasible: minimum >= reserve,
    events,
    balances,
  }
}

///|
/// Expand monthly income or obligations with month-end clamping.
pub fn recurring(
  first : Date,
  months : Int,
  cents : Int64,
  label : String,
) -> Array[Entry] raise InputError {
  if months < 1 || months > 120 {
    raise Invalid("recurrence months outside 1..120")
  }
  validate_money(cents, nonnegative=false)
  let events : Array[Entry] = []
  for i in 0..<months {
    events.push({ day: serial(add_months(first, i)), label, cents, })
  }
  events
}
