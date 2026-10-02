///|
pub fn validate_plan(plan : Plan) -> Unit raise InputError {
  validate_money(plan.cash_price_cents, nonnegative=true)
  validate_money(plan.down_cents, nonnegative=true)
  validate_money(plan.monthly_cents, nonnegative=true)
  if plan.cash_price_cents <= 0L ||
    plan.id == "" ||
    plan.months < 0 ||
    plan.months > 120 {
    raise Invalid("invalid plan id, price or repayment count")
  }
  if plan.months == 0 {
    if plan.down_cents != plan.cash_price_cents || plan.monthly_cents != 0L {
      raise Invalid("upfront plan must pay the full cash price")
    }
  } else if plan.down_cents >= plan.cash_price_cents || plan.monthly_cents <= 0L {
    raise Invalid("installments require positive financing and repayments")
  }
}

///|
/// All payments move with the purchase date. First installment one month later.
pub fn payment_schedule(
  plan : Plan,
  purchase : Date,
) -> Array[Entry] raise InputError {
  validate_plan(plan)
  let events : Array[Entry] = []
  if plan.down_cents > 0L {
    events.push({
      day: serial(purchase),
      label: plan.id,
      cents: -plan.down_cents,
    })
  }
  for i in 1..<=plan.months {
    events.push({
      day: serial(add_months(purchase, i)),
      label: plan.id,
      cents: -plan.monthly_cents,
    })
  }
  events
}

///|
pub fn plan_total(plan : Plan) -> Int64 raise InputError {
  validate_plan(plan)
  plan.down_cents + plan.monthly_cents * plan.months.to_int64()
}

///|
pub fn plan_xirr(plan : Plan, purchase : Date) -> Double? raise InputError {
  validate_plan(plan)
  if plan.months == 0 {
    return None
  }
  let flows : Array[Entry] = [
    {
      day: serial(purchase),
      label: "financing advance",
      cents: plan.cash_price_cents - plan.down_cents,
    },
  ]
  for e in payment_schedule(plan, purchase) {
    if e.day > serial(purchase) {
      flows.push(e)
    }
  }
  Some(xirr(flows))
}
