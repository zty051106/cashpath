///|
fn finite(value : Double) -> Bool {
  value == value && value > -1.0e300 && value < 1.0e300
}

///|
/// ACT/365 present value of dated signed flows at an effective annual rate.
pub fn present_value(
  flows : Array[Entry],
  anchor : Int,
  annual_rate : Double,
) -> Double raise InputError {
  if !finite(annual_rate) || annual_rate <= -1.0 || annual_rate > 10.0 {
    raise Invalid("effective annual rate must be finite in (-1, 10]")
  }
  let mut sum = 0.0
  for flow in flows {
    if flow.day < anchor {
      raise Invalid("flow precedes valuation date")
    }
    validate_money(flow.cents, nonnegative=false)
    sum = sum +
      flow.cents.to_double() /
      @math.pow(1.0 + annual_rate, (flow.day - anchor).to_double() / 365.0)
  }
  if !finite(sum) {
    raise Invalid("present value overflow")
  }
  sum
}

///|
/// Only one initial positive advance followed by negative repayments is supported.
/// This conventional financing stream is monotone and has at most one IRR.
fn financing_value(flows : Array[(Double, Double)], rate : Double) -> Double {
  let mut sum = 0.0
  for flow in flows {
    sum = sum + flow.0 / @math.pow(1.0 + rate, flow.1)
  }
  sum
}

///|
fn financing_irr(flows : Array[(Double, Double)]) -> Double raise InputError {
  if flows.length() < 2 ||
    !finite(flows[0].0) ||
    flows[0].0 <= 0.0 ||
    flows[0].1 != 0.0 {
    raise Invalid("IRR needs one initial positive financing advance")
  }
  let mut previous_time = 0.0
  for i in 1..<flows.length() {
    let (amount, time) = flows[i]
    if !finite(amount) ||
      !finite(time) ||
      amount >= 0.0 ||
      time <= previous_time {
      raise Invalid("IRR supports strictly later negative repayments only")
    }
    previous_time = time
  }
  let mut low = -0.999
  let mut high = 10.0
  if financing_value(flows, low) > 0.0 || financing_value(flows, high) < 0.0 {
    raise Invalid("IRR outside supported bracket [-99.9%, 1000%]")
  }
  for _ in 0..<100 {
    let mid = (low + high) / 2.0
    if financing_value(flows, mid) < 0.0 {
      low = mid
    } else {
      high = mid
    }
  }
  (low + high) / 2.0
}

///|
/// Monthly IRR; equal intervals only. Annualize as (1 + r)^12 - 1.
pub fn monthly_irr(
  advance : Int64,
  repayments : Array[Int64],
) -> Double raise InputError {
  validate_money(advance, nonnegative=true)
  let flows : Array[(Double, Double)] = [(advance.to_double(), 0.0)]
  if repayments.length() > 120 {
    raise Invalid("more than 120 repayments unsupported")
  }
  for i in 0..<repayments.length() {
    validate_money(repayments[i], nonnegative=true)
    flows.push((-repayments[i].to_double(), (i + 1).to_double()))
  }
  financing_irr(flows)
}

///|
pub fn annualize(monthly_rate : Double) -> Double raise InputError {
  if !finite(monthly_rate) || monthly_rate <= -1.0 || monthly_rate > 10.0 {
    raise Invalid("invalid monthly IRR")
  }
  @math.pow(1.0 + monthly_rate, 12.0) - 1.0
}

///|
/// Annual XIRR using actual days / 365. The initial advance is positive.
pub fn xirr(flows : Array[Entry]) -> Double raise InputError {
  if flows.length() < 2 || flows.length() > 121 {
    raise Invalid("XIRR requires 2..121 cash flows")
  }
  let anchor = flows[0].day
  let converted : Array[(Double, Double)] = []
  for flow in flows {
    ignore(date_from_serial(flow.day))
    validate_money(flow.cents, nonnegative=false)
    converted.push(
      (flow.cents.to_double(), (flow.day - anchor).to_double() / 365.0),
    )
  }
  financing_irr(converted)
}
