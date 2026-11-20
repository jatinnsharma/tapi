/// A national helpline number in India, dialled straight from the Safety
/// screen. Toll-free from any phone; 112 works without a SIM in most phones.
class Helpline {
  const Helpline(this.number, this.name, this.description);

  final String number;
  final String name;
  final String description;
}

/// India's national helplines, most important first.
const indiaHelplines = <Helpline>[
  Helpline(
    '112',
    'Emergency (all services)',
    'Single number for police, fire and ambulance across India.',
  ),
  Helpline('100', 'Police', 'Also reachable through 112.'),
  Helpline('108', 'Ambulance', 'Emergency medical services in most states.'),
  Helpline('101', 'Fire', 'Fire and rescue services.'),
  Helpline('1091', 'Women helpline', 'Women in distress, police response.'),
  Helpline('181', 'Women helpline (state)', 'Support line in most states.'),
  Helpline('1098', 'Child helpline', 'Children in need of care or help.'),
  Helpline(
    '1363',
    'Tourist helpline',
    'India Tourism infoline for travellers.',
  ),
  Helpline(
    '1078',
    'Disaster helpline',
    'National Disaster Management Authority.',
  ),
];
