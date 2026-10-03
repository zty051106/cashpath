///|
fn field(value : Json, name : String) -> Json raise InputError {
  match value {
    Object(obj) =>
      match obj.get(name) {
        Some(value) => value
        None => raise Invalid("missing field: \{name}")
      }
    _ => raise Invalid("expected an object")
  }
}

///|

///|
fn text_value(value : Json) -> String raise InputError {
  match value {
    String(s) => s
    _ => raise Invalid("expected a string")
  }
}

///|
fn number_value(value : Json) -> Double raise InputError {
  match value {
    Number(n, ..) if finite(n) => n
    _ => raise Invalid("expected a finite number")
  }
}

///|
fn integer_value(value : Json, low : Int, high : Int) -> Int raise InputError {
  let n = number_value(value)
  if n != @math.floor(n) || n < low.to_double() || n > high.to_double() {
    raise Invalid("integer outside \{low}..\{high}")
  }
  n.to_int()
}

///|
fn money_value(value : Json) -> Int64 raise InputError {
  let n = number_value(value)
  if n != @math.floor(n) || n < 0.0 || n > 1000000000000.0 {
    raise Invalid("money must be integer cents in 0..1000000000000")
  }
  n.to_int64()
}

///|
fn array_value(value : Json, maximum : Int) -> Array[Json] raise InputError {
  match value {
    Array(xs) if xs.length() <= maximum => xs
    _ => raise Invalid("expected array with at most \{maximum} items")
  }
}

///|
fn parsed_date(value : Json) -> Date raise InputError {
  let parts = text_value(value).split("-").collect()
  if parts.length() != 3 {
    raise Invalid("expected ISO date YYYY-MM-DD")
  }
  let y = decimal_digits(parts[0])
  let m = decimal_digits(parts[1])
  let d = decimal_digits(parts[2])
  let result = date(y, m, d)
  if date_text(serial(result)) != text_value(value) {
    raise Invalid("expected canonical YYYY-MM-DD")
  }
  result
}

///|
fn decimal_digits(value : StringView) -> Int raise InputError {
  if value.length() == 0 || value.length() > 4 {
    raise Invalid("invalid calendar number")
  }
  let mut result = 0
  for ch in value.to_owned().iter() {
    if ch < '0' || ch > '9' {
      raise Invalid("invalid calendar number")
    }
    result = result * 10 + ch.to_int() - '0'.to_int()
  }
  result
}

///|
fn path_json(path : Path, detailed~ : Bool) -> Json raise InputError {
  let breach : Json = match path.first_breach {
    None => Json::null()
    Some(e) => { "date": date_text(e.day), "event": e.label }
  }
  let events : Array[Json] = []
  for i in 0..<(if detailed { path.events.length() } else { 0 }) {
    let e = path.events[i]
    events.push({
      "date": date_text(e.day),
      "event": e.label,
      "change_cents": e.cents.to_string(),
      "balance_cents": path.balances[i].to_string(),
    })
  }
  {
    "feasible": path.feasible,
    "ending_cents": path.ending_cents.to_string(),
    "minimum_cents": path.minimum_cents.to_string(),
    "minimum_date": date_text(path.minimum_day),
    "peak_shortfall_cents": path.peak_shortfall_cents.to_string(),
    "first_breach": breach,
    "events": events,
  }
}

///|
/// Parse supported v0.1 input, compute in MoonBit and return a traceable JSON report.
pub fn analyze(raw : String) -> Json raise InputError {
  if raw.length() > 200000 {
    raise Invalid("input larger than 200000 characters")
  }
  let input = @json.parse(raw) catch { _ => raise Invalid("invalid JSON") }
  if text_value(field(input, "schema_version")) != "0.1" ||
    text_value(field(input, "currency")) != "CNY" ||
    text_value(field(input, "same_day_order")) != "outflows_before_inflows" {
    raise Invalid("requires schema 0.1, CNY and outflows_before_inflows")
  }
  let start = parsed_date(field(input, "start_date"))
  if start.day != 1 {
    raise Invalid("v0.1 starts on the first day of a month")
  }
  let months = integer_value(field(input, "evaluation_horizon_months"), 1, 24)
  let end = date_from_serial(serial(add_months(start, months)) - 1)
  let delay_limit = integer_value(
    field(input, "max_purchase_delay_days"),
    0,
    90,
  )
  let discount = number_value(field(input, "annual_effective_discount_rate"))
  let opening = money_value(field(input, "opening_balance_cents"))
  let reserve = money_value(field(input, "reserve_floor_cents"))
  let ledger : Array[Entry] = []
  let ids : Map[String, Bool] = Map([])
  for item in array_value(field(input, "recurring_events"), 20) {
    let id = text_value(field(item, "id"))
    if id == "" || ids.contains(id) {
      raise Invalid("recurring event ids must be nonempty and unique")
    }
    ids.set(id, true)
    let cents = money_value(field(item, "amount_cents"))
    let kind = text_value(field(item, "kind"))
    let signed = match kind {
      "income" => cents
      "expense" => -cents
      _ => raise Invalid("recurring kind must be income or expense")
    }
    let dom = integer_value(field(item, "day_of_month"), 1, 31)
    for i in 0..<months {
      let base = add_months(start, i)
      let day = if dom < month_days(base.year, base.month) {
        dom
      } else {
        month_days(base.year, base.month)
      }
      ledger.push({
        day: serial(date(base.year, base.month, day)),
        label: id,
        cents: signed,
      })
    }
  }
  let purchase_input = field(input, "purchase")
  let purchase = parsed_date(field(purchase_input, "preferred_date"))
  let price = money_value(field(purchase_input, "cash_price_cents"))
  let plans : Array[Plan] = []
  let plan_ids : Map[String, Bool] = Map([])
  let rates : Array[Json] = []
  for item in array_value(field(purchase_input, "plans"), 4) {
    let id = text_value(field(item, "id"))
    if plan_ids.contains(id) {
      raise Invalid("duplicate payment plan id")
    }
    plan_ids.set(id, true)
    let kind = text_value(field(item, "kind"))
    let plan : Plan = match kind {
      "upfront" =>
        {
          id,
          cash_price_cents: price,
          down_cents: money_value(field(item, "payment_cents")),
          monthly_cents: 0L,
          months: 0,
        }
      "fixed_monthly" => {
        if field(item, "fee_included_in_payment") != true ||
          integer_value(field(item, "first_payment_month_offset"), 1, 1) != 1 {
          raise Invalid(
            "fees must be included; first payment is one month later",
          )
        }
        {
          id,
          cash_price_cents: price,
          down_cents: money_value(field(item, "down_payment_cents")),
          monthly_cents: money_value(field(item, "payment_cents")),
          months: integer_value(field(item, "number_of_payments"), 1, 120),
        }
      }
      _ => raise Invalid("unsupported payment kind")
    }
    validate_plan(plan)
    plans.push(plan)
    let (annual, status) : (Json, String) = try {
      match plan_xirr(plan, purchase) {
        None => (Json::null(), "not_financing")
        Some(rate) => (rate.to_json(), "solved")
      }
    } catch {
      _ => (Json::null(), "outside_supported_rate_bracket")
    }
    rates.push({
      "id": id,
      "annual_xirr": annual,
      "status": status,
      "total_cents": plan_total(plan).to_string(),
    })
  }
  let ledgers : Array[(String, Array[Entry])] = []
  let stress_ids : Map[String, Bool] = Map([])
  for item in array_value(field(input, "stress_scenarios"), 4) {
    let id = text_value(field(item, "id"))
    if id == "" || stress_ids.contains(id) {
      raise Invalid("scenario ids must be nonempty and unique")
    }
    stress_ids.set(id, true)
    let stress_kind = text_value(field(item, "kind"))
    if id == "baseline" && stress_kind != "baseline" {
      raise Invalid("baseline id must use baseline kind")
    }
    let stress : Stress = match stress_kind {
      "baseline" => Baseline
      "delay_event" =>
        Delay(
          text_value(field(item, "event_id")),
          serial(parsed_date(field(item, "occurrence_date"))),
          integer_value(field(item, "delay_days"), 1, 365),
        )
      "scale_income" => {
        let factor = number_value(field(item, "factor"))
        let percent = @math.round(factor * 100.0)
        if factor < 0.0 ||
          factor > 1.0 ||
          (percent - factor * 100.0).abs() > 1.0e-8 {
          raise Invalid(
            "income factor must use whole retained percentages from 0 to 100",
          )
        }
        IncomeDrop(
          text_value(field(item, "event_id")),
          serial(parsed_date(field(item, "start_date"))),
          serial(parsed_date(field(item, "end_date"))),
          percent.to_int(),
        )
      }
      "add_expense" =>
        ExtraExpense(
          serial(parsed_date(field(item, "date"))),
          money_value(field(item, "amount_cents")),
        )
      _ => raise Invalid("unsupported stress scenario")
    }
    ledgers.push((id, apply_stress(ledger, stress)))
  }
  // Baseline is mandatory to make every stress report comparable.
  if !stress_ids.contains("baseline") {
    raise Invalid("include a baseline scenario with id baseline")
  }
  let delays : Array[Int] = []
  for i in 0..<=delay_limit {
    delays.push(i)
  }
  let candidates = compare(
    opening, reserve, start, end, purchase, delays, plans, ledgers, discount,
  )
  let summaries : Array[Json] = []
  for c in candidates {
    let outcomes : Array[Json] = []
    let mut worst_name = ""
    for (name, p) in c.scenarios {
      if worst_name == "" && p.minimum_cents == c.worst_path.minimum_cents {
        worst_name = name
      }
      outcomes.push({ "id": name, "path": path_json(p, detailed=false) })
    }
    summaries.push({
      "id": c.id,
      "delay_days": c.delay_days,
      "total_cents": c.total_cents.to_string(),
      "present_value_cents": c.present_value_cents,
      "worst_scenario": worst_name,
      "worst_path": path_json(c.worst_path, detailed=true),
      "scenarios": outcomes,
    })
  }
  let frontier : Array[String] = []
  for c in pareto(candidates) {
    frontier.push(c.id)
  }
  {
    "schema_version": "0.1",
    "name": text_value(field(input, "name")),
    "currency": "CNY",
    "evaluation_start": date_text(serial(start)),
    "evaluation_end": date_text(serial(end)),
    "reserve_floor_cents": reserve.to_string(),
    "assumptions": {
      "same_day_order": "outflows_before_inflows",
      "discount_rate": discount,
      "day_count": "ACT/365",
      "stress_is_probability": false,
      "pareto_dimensions": [
        "present_value_cents", "worst_minimum_cents", "delay_days",
      ],
    },
    "input": input,
    "rates_reference_purchase_date": date_text(serial(purchase)),
    "rates": rates,
    "candidates": summaries,
    "pareto_ids": frontier,
  }
}

///|
/// Browser / Node entry point. No network, no AI or hidden state involved.
pub fn analyze_json(raw : String) -> String {
  analyze(raw).stringify() catch {
    Invalid(message) => {
      let result : Json = { "error": message }
      result.stringify()
    }
  }
}
