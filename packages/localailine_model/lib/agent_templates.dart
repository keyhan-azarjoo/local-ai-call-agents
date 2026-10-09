/// Ready-made roles for common businesses: pick one and the agent arrives with its job, when
/// calls should come to it, how to behave, and what it can do (take messages, book, take orders).
class RoleTemplate {
  const RoleTemplate(this.name, this.role, this.when, this.instructions, {this.abilities = const [], this.voice, this.person = false, this.answers = false});
  final String name, role, when, instructions;
  final List<String> abilities;
  final String? voice;
  final bool person; // a real person (manager/owner), rung by phone or app
  final bool answers; // the receptionist: answers every call
}

class BusinessTemplate {
  const BusinessTemplate(this.id, this.label, this.icon, this.roles);
  final String id, label, icon;
  final List<RoleTemplate> roles;
}

const _reception =
    'Greet the caller warmly, find out what they need and help with simple questions (opening hours, location, prices) from your documents. '
    'If something is another team member’s job, pass the call to them. If nobody can help right now, take a message: name, number and what it’s about, then read it back.';

const businessTemplates = <BusinessTemplate>[
  BusinessTemplate('restaurant', 'Restaurant / café', '🍽️', [
    RoleTemplate('Ava', 'Receptionist', '', _reception, abilities: ['message'], answers: true),
    RoleTemplate('Sam', 'Order taker', 'The caller wants to place a takeaway or delivery order.',
        'You take takeaway and delivery orders. Use the menu, prices, allergens and delivery zones from your documents only. '
            'Take the items one by one, ask about allergies, check the postcode for delivery, then read the order back with the total and save it.',
        abilities: ['order'], voice: 'kokoro:am_michael'),
    RoleTemplate('Lily', 'Bookings', 'The caller wants to book a table or change or cancel a reservation.',
        'You handle table bookings: date, time, number of people, name and mobile number, any occasion or accessibility needs. '
            'Check the opening hours, read the booking back, then save it.',
        abilities: ['booking'], voice: 'kokoro:bf_emma'),
    RoleTemplate('Manager', 'Manager (person)', 'The caller asks for a manager, has a complaint, or wants a refund.', '', person: true),
  ]),
  BusinessTemplate('salon', 'Barber / hair & beauty salon', '💈', [
    RoleTemplate('Ava', 'Receptionist', '', _reception, abilities: ['message'], answers: true),
    RoleTemplate('Mia', 'Appointments', 'The caller wants to book, move or cancel an appointment.',
        'You book appointments: which service (from the price list), preferred stylist if any, date and time, name and mobile number. '
            'Suggest the nearest free times if their first choice doesn’t work, read the booking back, then save it.',
        abilities: ['booking'], voice: 'kokoro:af_bella'),
    RoleTemplate('Owner', 'Owner (person)', 'The caller asks for the owner or a specific stylist, or has a complaint.', '', person: true),
  ]),
  BusinessTemplate('clinic', 'Clinic / dentist / therapist', '🩺', [
    RoleTemplate('Ava', 'Receptionist', '', '$_reception Never give medical advice; for anything urgent tell them to call the emergency number.', abilities: ['message'], answers: true),
    RoleTemplate('Nora', 'Appointments', 'The caller wants to book, move or cancel an appointment.',
        'You book appointments: new or existing patient, reason in a few words, preferred days and times, name, date of birth and mobile number. '
            'Read the booking back, then save it. Never give medical advice.',
        abilities: ['booking'], voice: 'kokoro:bf_isabella'),
    RoleTemplate('Practice manager', 'Practice manager (person)', 'The caller has a complaint, a billing question, or asks for a person.', '', person: true),
  ]),
  BusinessTemplate('shop', 'Shop / online store', '🛍️', [
    RoleTemplate('Ava', 'Receptionist', '', _reception, abilities: ['message'], answers: true),
    RoleTemplate('Leo', 'Orders & stock', 'The caller wants to order something, check stock, or ask about an existing order.',
        'You help with products, stock and orders using your documents and connected systems. Take new orders item by item, read them back with the total, then save them.',
        abilities: ['order'], voice: 'kokoro:am_fenrir'),
    RoleTemplate('Returns', 'Returns & refunds', 'The caller wants to return something or get a refund.',
        'You handle returns: order details, what is wrong, whether they want a refund or exchange. Follow the returns policy in your documents and take a message for anything beyond it.',
        abilities: ['message'], voice: 'kokoro:bf_emma'),
    RoleTemplate('Manager', 'Manager (person)', 'The caller asks for a manager or has a complaint.', '', person: true),
  ]),
  BusinessTemplate('office', 'Office / professional services', '💼', [
    RoleTemplate('Ava', 'Receptionist', '', _reception, abilities: ['message', 'booking'], answers: true),
    RoleTemplate('Support', 'Customer support', 'The caller is an existing customer with a question or problem.',
        'You help existing customers using your documents and connected systems. If you can’t solve it, take a detailed message for the team.',
        abilities: ['message'], voice: 'kokoro:am_michael'),
    RoleTemplate('Sales', 'New enquiries', 'The caller is interested in buying or wants a quote.',
        'You answer questions from new customers, find out what they need and book a call or meeting with the team.',
        abilities: ['booking', 'message'], voice: 'kokoro:af_nicole'),
    RoleTemplate('Me', 'Me (person)', 'The caller asks for me by name, or it is urgent.', '', person: true),
  ]),
  BusinessTemplate('hotel', 'Hotel / B&B / rentals', '🏨', [
    RoleTemplate('Ava', 'Front desk', '', _reception, abilities: ['message'], answers: true),
    RoleTemplate('Ella', 'Reservations', 'The caller wants to book, change or cancel a stay.',
        'You take reservations: dates, number of guests, room type, name and mobile number, arrival time and any requests. Read it back, then save it.',
        abilities: ['booking'], voice: 'kokoro:bf_emma'),
    RoleTemplate('Duty manager', 'Duty manager (person)', 'The caller has a complaint or an urgent problem during their stay.', '', person: true),
  ]),
];

/// Single roles to add one at a time, whatever the business.
const extraRoles = <RoleTemplate>[
  RoleTemplate('Receptionist', 'Receptionist', 'The caller has a general question or needs to leave a message.', _reception, abilities: ['message']),
  RoleTemplate('Bookings', 'Bookings', 'The caller wants to book, move or cancel an appointment or table.',
      'You take bookings: what for, date and time, name and mobile number. Read the booking back, then save it.', abilities: ['booking']),
  RoleTemplate('Orders', 'Order taker', 'The caller wants to place an order.',
      'You take orders using your documents for products and prices. Read the order back with the total, then save it.', abilities: ['order']),
  RoleTemplate('Support', 'Support', 'The caller has a problem or question about something they bought or use.',
      'You help with problems using your documents and connected systems; take a detailed message if you can’t solve it.', abilities: ['message']),
  RoleTemplate('Billing', 'Billing & payments', 'The caller has a question about a bill, payment or refund.',
      'You answer billing questions from your documents and connected systems. Never take card numbers on the phone; take a message for anything you can’t settle.',
      abilities: ['message']),
];

/// What an agent can do on a call with no connected system (see the engine's Abilities).
const abilityLabels = {
  'message': 'Take messages',
  'booking': 'Book appointments / tables',
  'order': 'Take orders',
};
