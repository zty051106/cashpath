///|
/// Evaluate all supplied stress ledgers over one shared, full horizon.
pub fn compare(
  opening : Int64,
  reserve : Int64,
  start : Date,
  end : Date,
  purchase : Date,
  delays : Array[Int],
  plans : Array[Plan],
  ledgers : Array[(String, Array[Entry])],
  annual_discount : Double,
) -> Array[Candidate] raise InputError {
  let start_day = serial(start)
  let end_day = serial(end)
  let purchase_day = serial(purchase)
  if purchase_day < start_day ||
    delays.is_empty() ||
    delays.length() > 91 ||
    plans.is_empty() ||
    plans.length() > 10 ||
    ledgers.is_empty() ||
    ledgers.length() > 8 {
    raise Invalid("invalid purchase date or candidate dimensions")
  }
  let candidates : Array[Candidate] = []
  for delay in delays {
    if delay < 0 || delay > 90 {
      raise Invalid("purchase delay outside 0..90 days")
    }
    let shifted = date_from_serial(purchase_day + delay)
    for plan in plans {
      let payments = payment_schedule(plan, shifted)
      if serial(shifted) > end_day {
        raise Invalid("purchase outside evaluation horizon")
      }
      let scenarios : Array[(String, Path)] = []
      let mut worst : Path? = None
      for (name, ledger) in ledgers {
        let combined = ledger.copy()
        combined.append(payments)
        let path = simulate(opening, reserve, start_day, end_day, combined)
        scenarios.push((name, path))
        match worst {
          None => worst = Some(path)
          Some(previous) =>
            if path.minimum_cents < previous.minimum_cents {
              worst = Some(path)
            }
        }
      }
      candidates.push({
        id: "\{plan.id}+\{delay}d",
        delay_days: delay,
        total_cents: plan_total(plan),
        present_value_cents: -present_value(
          payments, start_day, annual_discount,
        ),
        worst_path: worst.unwrap(),
        scenarios,
      })
    }
  }
  candidates
}

///|
/// Pareto dimensions: lower PV, higher worst-case minimum balance, less waiting.
pub fn pareto(candidates : Array[Candidate]) -> Array[Candidate] {
  let kept : Array[Candidate] = []
  for candidate in candidates {
    if !candidate.worst_path.feasible {
      continue
    }
    let mut dominated = false
    for other in candidates {
      if !other.worst_path.feasible {
        continue
      }
      let cheaper = other.present_value_cents <= candidate.present_value_cents
      let liquid = other.worst_path.minimum_cents >=
        candidate.worst_path.minimum_cents
      let sooner = other.delay_days <= candidate.delay_days
      let strict = other.present_value_cents < candidate.present_value_cents ||
        other.worst_path.minimum_cents > candidate.worst_path.minimum_cents ||
        other.delay_days < candidate.delay_days
      if cheaper && liquid && sooner && strict {
        dominated = true
        break
      }
    }
    if !dominated {
      kept.push(candidate)
    }
  }
  kept
}
