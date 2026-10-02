///|
fn leap(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn month_days(year : Int, month : Int) -> Int {
  match month {
    2 => if leap(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
pub fn date(year : Int, month : Int, day : Int) -> Date raise InputError {
  if year < 2000 || year > 2100 || month < 1 || month > 12 {
    raise Invalid("date must be between 2000-01-01 and 2100-12-31")
  }
  if day < 1 || day > month_days(year, month) {
    raise Invalid("invalid calendar day")
  }
  { year, month, day, }
}

///|
/// Days since 2000-01-01; ACT/365 uses differences of these serials.
pub fn serial(value : Date) -> Int raise InputError {
  let d = date(value.year, value.month, value.day)
  let mut days = d.day - 1
  for y in 2000..<d.year {
    days = days + (if leap(y) { 366 } else { 365 })
  }
  for m in 1..<d.month {
    days = days + month_days(d.year, m)
  }
  days
}

///|
/// Month-end clamp, always anchored to the original day (Jan 31 -> Mar 31).
pub fn add_months(value : Date, offset : Int) -> Date raise InputError {
  ignore(date(value.year, value.month, value.day))
  if offset < 0 || offset > 120 {
    raise Invalid("month offset outside 0..120")
  }
  let months = value.month - 1 + offset
  let year = value.year + months / 12
  let month = months % 12 + 1
  let day = if value.day < month_days(year, month) {
    value.day
  } else {
    month_days(year, month)
  }
  date(year, month, day)
}

///|
pub fn date_from_serial(day : Int) -> Date raise InputError {
  if day < 0 || day > serial(date(2100, 12, 31)) {
    raise Invalid("day outside supported calendar")
  }
  let mut rest = day
  let mut year = 2000
  while rest >= (if leap(year) { 366 } else { 365 }) {
    rest = rest - (if leap(year) { 366 } else { 365 })
    year = year + 1
  }
  let mut month = 1
  while rest >= month_days(year, month) {
    rest = rest - month_days(year, month)
    month = month + 1
  }
  date(year, month, rest + 1)
}

///|
pub fn date_text(day : Int) -> String raise InputError {
  let d = date_from_serial(day)
  let mm = if d.month < 10 { "0\{d.month}" } else { "\{d.month}" }
  let dd = if d.day < 10 { "0\{d.day}" } else { "\{d.day}" }
  "\{d.year}-\{mm}-\{dd}"
}
