import 'package:flutter/material.dart';

import 'planner_input.dart';
import 'trip_plan.dart';

// Rule-based extras for a saved trip: a packing checklist, a rough budget,
// booking links and a season note. No AI involved, so they work offline and
// cost nothing.

// ---------------------------------------------------------------------------
// Season
// ---------------------------------------------------------------------------

enum IndiaSeason { winter, summer, monsoon, postMonsoon }

IndiaSeason seasonFor(DateTime date) => switch (date.month) {
  12 || 1 || 2 => IndiaSeason.winter,
  3 || 4 || 5 => IndiaSeason.summer,
  6 || 7 || 8 || 9 => IndiaSeason.monsoon,
  _ => IndiaSeason.postMonsoon,
};

/// A one-line heads-up about travelling in [date]'s season. Broad strokes:
/// India's climate varies a lot, so the forecast (when in range) is the real
/// guide.
String seasonNote(DateTime date) => switch (seasonFor(date)) {
  IndiaSeason.winter => 'Winter: pleasant days in the plains, cold nights up north and foggy mornings that can delay trains and flights.',
  IndiaSeason.summer => 'Summer: hot afternoons across most of India, so plan sights for early morning and evening. Ideal for the hills.',
  IndiaSeason.monsoon => 'Monsoon: expect rain, lush green views and possible landslides on mountain roads. Keep spare time in the plan.',
  IndiaSeason.postMonsoon => 'Post-monsoon: one of the best times to travel, with clear skies and festivals like Dussehra and Diwali.',
};

// ---------------------------------------------------------------------------
// Packing
// ---------------------------------------------------------------------------

class PackingSection {
  const PackingSection(this.title, this.icon, this.items);

  final String title;
  final IconData icon;
  final List<String> items;
}

bool _hasInterest(TripPlan plan, String needle) =>
    plan.interests.any((i) => i.toLowerCase().contains(needle.toLowerCase()));

/// The checklist for [plan]. Items are stable strings, so the ones the user
/// ticked ([TripPlan.packingChecked]) still match after the list is rebuilt.
List<PackingSection> packingListFor(TripPlan plan) {
  final season = plan.startDate == null ? null : seasonFor(plan.startDate!);
  final nights = plan.daysCount;

  final clothes = <String>[
    '${nights + 1} sets of comfortable clothes',
    'Comfortable walking shoes',
    'Sleepwear',
    if (season == IndiaSeason.winter) ...[
      'Warm jacket or sweater',
      'Thermals for the nights',
    ],
    if (season == IndiaSeason.summer) ...[
      'Light cotton clothes',
      'Sun hat or cap',
    ],
    if (season == IndiaSeason.monsoon) ...[
      'Umbrella or rain jacket',
      'Quick-dry clothes and sandals',
    ],
    if (_hasInterest(plan, 'spiritual') || _hasInterest(plan, 'heritage'))
      'Modest clothes covering shoulders and knees (temples)',
    if (_hasInterest(plan, 'spiritual')) 'Socks for temple floors',
    if (_hasInterest(plan, 'adventure') || _hasInterest(plan, 'nature'))
      'Trekking shoes and a light backpack',
  ];

  final health = <String>[
    'Personal medicines',
    'Basic first-aid kit',
    'ORS sachets',
    'Hand sanitiser and wet wipes',
    'Sunscreen',
    if (season == IndiaSeason.monsoon || season == IndiaSeason.postMonsoon)
      'Mosquito repellent',
    if (plan.companion == TripCompanion.family) 'Snacks and medicines for kids',
  ];

  final documents = <String>[
    'Government photo ID (Aadhaar / passport / driving licence)',
    'Train / flight / bus tickets',
    'Hotel booking confirmations',
    'Some cash in small notes',
    'UPI app set up, plus a debit or credit card',
  ];

  final gadgets = <String>[
    'Phone charger',
    'Power bank',
    'Earphones',
    if (_hasInterest(plan, 'photo')) 'Camera, spare batteries and memory card',
  ];

  final extras = <String>[
    'Reusable water bottle',
    'Small daypack',
    'Scarf or stole (sun, dust or temples)',
    if (plan.companion == TripCompanion.friends)
      'Card game or speaker for downtime',
  ];

  return [
    PackingSection('Clothes', Icons.checkroom_outlined, clothes),
    PackingSection('Health', Icons.medical_services_outlined, health),
    PackingSection('Documents & money', Icons.badge_outlined, documents),
    PackingSection('Gadgets', Icons.power_outlined, gadgets),
    PackingSection('Handy extras', Icons.backpack_outlined, extras),
  ];
}

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------

class BudgetLine {
  const BudgetLine(this.label, this.icon, this.low, this.high);

  final String label;
  final IconData icon;

  /// Rupees for the whole group and the whole trip.
  final int low;
  final int high;
}

class BudgetEstimate {
  const BudgetEstimate(this.lines, this.travellers, this.nights);

  final List<BudgetLine> lines;
  final int travellers;
  final int nights;

  int get low => lines.fold(0, (sum, l) => sum + l.low);
  int get high => lines.fold(0, (sum, l) => sum + l.high);
  int get perPersonLow => (low / travellers).round();
  int get perPersonHigh => (high / travellers).round();
}

/// Big cities and beach hubs where stays and cabs cost more.
const _pricierDestinations = {
  'mumbai',
  'new delhi',
  'delhi',
  'bengaluru',
  'bangalore',
  'goa',
  'gurugram',
  'hyderabad',
  'chennai',
  'pune',
  'kolkata',
  'udaipur',
  'leh',
};

/// A rough range for [plan] in rupees, excluding getting to the destination.
/// Rates are typical 2026 prices per tier; it's a planning aid, not a quote.
BudgetEstimate estimateBudget(TripPlan plan) {
  final people = plan.travellerCount;
  final nights = plan.daysCount; // Arriving day 1, leaving after the last day.
  final rooms = (people / 2).ceil();
  final pricey = _pricierDestinations.contains(plan.destination.toLowerCase());
  final m = pricey ? 1.25 : 1.0;

  // [low, high] per room per night, per person per day, per group per day.
  final (stay, food, transport, entries) = switch (plan.budget) {
    TripBudget.budget => ((800, 1800), (400, 700), (200, 500), (100, 300)),
    TripBudget.moderate => ((2500, 5000), (900, 1600), (600, 1500), (300, 800)),
    TripBudget.luxury => (
      (8000, 20000),
      (2500, 5000),
      (2500, 5000),
      (800, 2500),
    ),
  };

  int r(double v) => (v / 100).round() * 100; // Round to the nearest ₹100.

  return BudgetEstimate(
    [
      BudgetLine(
        'Stay ($rooms room${rooms == 1 ? '' : 's'})',
        Icons.hotel_outlined,
        r(stay.$1 * rooms * nights * m),
        r(stay.$2 * rooms * nights * m),
      ),
      BudgetLine(
        'Food',
        Icons.restaurant_outlined,
        r(food.$1 * people * nights * m),
        r(food.$2 * people * nights * m),
      ),
      BudgetLine(
        'Local transport',
        Icons.local_taxi_outlined,
        r(transport.$1 * nights * m),
        r(transport.$2 * nights * m),
      ),
      BudgetLine(
        'Entry tickets & activities',
        Icons.confirmation_number_outlined,
        r(entries.$1 * people * nights * 1.0),
        r(entries.$2 * people * nights * 1.0),
      ),
    ],
    people,
    nights,
  );
}

/// "₹12,500" style.
String formatRupees(int amount) {
  final digits = amount.toString();
  if (digits.length <= 3) return '₹$digits';
  // Indian grouping: last three digits, then pairs (12,34,567).
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}

// ---------------------------------------------------------------------------
// Booking links
// ---------------------------------------------------------------------------

class BookingLink {
  const BookingLink(this.label, this.subtitle, this.icon, this.url);

  final String label;
  final String subtitle;
  final IconData icon;
  final Uri url;
}

/// Where to book stays and travel. These are searches on public sites, not
/// partner deals; the ecosystem screens stay off until they have real data.
List<BookingLink> bookingLinksFor(TripPlan plan) {
  final dest = plan.destination;
  final from = plan.travelingFrom;
  final route = from == null ? 'to $dest' : 'from $from to $dest';
  return [
    BookingLink(
      'Hotels & stays',
      'Places to stay in $dest on Google Maps',
      Icons.hotel_outlined,
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': 'hotels in $dest',
      }),
    ),
    BookingLink(
      'Trains',
      'Book on IRCTC',
      Icons.train_outlined,
      Uri.https('www.irctc.co.in', '/nget/train-search'),
    ),
    BookingLink(
      'Buses',
      'Search buses $route on redBus',
      Icons.directions_bus_outlined,
      Uri.https('www.redbus.in', '/'),
    ),
    BookingLink(
      'Flights',
      'Flights $route on Google Flights',
      Icons.flight_outlined,
      Uri.https('www.google.com', '/travel/flights', {'q': 'flights $route'}),
    ),
  ];
}
