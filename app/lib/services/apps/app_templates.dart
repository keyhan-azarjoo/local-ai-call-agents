/// Ready-made apps for common businesses: open one, change the details, done.
/// No AI is needed to start; the AI can change any part afterwards.
library;

class AppTemplate {
  const AppTemplate(this.id, this.name, this.blurb, this.spec, this.rows);
  final String id, name, blurb;

  /// An app description (see [AppSpec.fromJson]).
  final Map<String, Object?> spec;

  /// Example records per table; links name the other record (e.g. a dish by its name).
  /// Pictures are `unsplash:<id>`: downloaded into the app when it is made (free Unsplash photos).
  final Map<String, List<Map<String, Object?>>> rows;
}

Map<String, Object?> _f(String id, String label, String type, {bool req = false, List<String>? options, String? link, bool qty = false, bool manager = false, Map<String, List<String>>? when}) =>
    {'id': id, 'label': label, 'type': type, if (req) 'required': true, 'options': ?options, 'link': ?link, if (qty) 'qty': true, if (manager) 'manager_only': true, 'when': ?when};

Map<String, Object?> _t(String id, String title, String purpose, String access, List<Map<String, Object?>> fields, {bool single = false}) =>
    {'id': id, 'title': title, 'purpose': purpose, 'kind': single ? 'single' : 'list', 'access': access, 'fields': fields};

Map<String, Object?> _hero(String title, String text, {String? button, String? link}) => {'type': 'hero', 'title': title, 'text': text, 'button': ?button, 'link': ?link};
Map<String, Object?> _list(String table, String title, {bool search = true}) => {'type': 'list', 'table': table, 'title': title, 'search': search};
Map<String, Object?> _form(String table, String title, String submit, String thanks) => {'type': 'form', 'table': table, 'title': title, 'submit': submit, 'thanks': thanks};
Map<String, Object?> _info(String table, String title) => {'type': 'info', 'table': table, 'title': title};
Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};
Map<String, Object?> _features(String title, List<String> lines) => {'type': 'features', 'title': title, 'text': lines.join('\n')};

final _hours = _t('opening_hours', 'Opening hours', 'When you are open', 'see', [_f('opens', 'Opens', 'time'), _f('closes', 'Closes', 'time'), _f('days', 'Days', 'text')], single: true);

final appTemplates = <AppTemplate>[
  AppTemplate('restaurant', 'Restaurant', 'Menu with photos, orders for collection, delivery or to your table, reservations and opening hours.', {
    'name': 'Trattoria Bella',
    'summary': 'Guests browse the menu, order to their table and book ahead.',
    'site': {'style': 'elegant', 'tagline': 'Wood-fired pizza & handmade pasta', 'hero': 'unsplash:1414235077428-338989a2e8c0', 'about': 'A family trattoria serving the food of Naples since 1998: slow-proved dough, fresh pasta every morning and wine from small Italian growers.', 'address': '12 Harbour Street', 'phone': '020 7946 0123', 'email': 'ciao@trattoriabella.example', 'currency': '£', 'footer': 'Free Wi-Fi · Dogs welcome on the terrace'},
    'tables': [
      _t('menu_items', 'Menu', 'Dishes and drinks with prices', 'see', [
        _f('name', 'Dish', 'text', req: true), _f('category', 'Category', 'choice', options: ['Starters', 'Pizza', 'Pasta', 'Desserts', 'Drinks', 'Sides']),
        _f('description', 'Description', 'longtext'), _f('price', 'Price', 'money', req: true), _f('photo', 'Photo', 'image'),
        _f('vegetarian', 'Vegetarian', 'yesno'), _f('spicy', 'Spicy', 'yesno'),
        _f('allergens', 'Allergens', 'text'), _f('vegan', 'Vegan', 'yesno'), _f('gluten_free', 'Gluten free', 'yesno'), _f('popular', 'Popular', 'yesno'),
        _f('available', 'Available today', 'yesno'),
      ]),
      _t('dining_tables', 'Tables', 'Tables in the restaurant', 'see', [_f('number', 'Table', 'text', req: true), _f('seats', 'Seats', 'number'), _f('area', 'Area', 'choice', options: ['Inside', 'Terrace', 'Window'])]),
      _t('orders', 'Orders', 'Food orders: collection, delivery or to a table', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true),
        _f('type', 'Collection or delivery', 'choice', options: ['Collection', 'Delivery', 'Dine-in'], req: true),
        _f('address', 'Delivery address', 'text', req: true, when: {'type': ['Delivery']}), _f('postcode', 'Postcode', 'text', req: true, when: {'type': ['Delivery']}),
        _f('table', 'Your table', 'link', link: 'dining_tables', req: true, when: {'type': ['Dine-in']}),
        _f('ready_at', 'Ready / delivered at', 'time'),
        _f('items', 'Your order', 'links', link: 'menu_items', qty: true, req: true),
        _f('notes', 'Notes for the kitchen (allergies…)', 'longtext'), _f('status', 'Status', 'choice', options: ['New', 'Preparing', 'Ready', 'Out for delivery', 'Done', 'Cancelled'], manager: true),
        _f('payment', 'Payment', 'choice', options: ['Unpaid', 'Paid card', 'Paid cash'], manager: true), _f('total', 'Total', 'money', manager: true),
      ]),
      _t('reservations', 'Reservations', 'Table bookings', 'add', [
        _f('name', 'Name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('date', 'Date', 'date', req: true), _f('time', 'Time', 'time', req: true),
        _f('guests', 'Guests', 'number', req: true), _f('table', 'Table', 'link', link: 'dining_tables'), _f('requests', 'Special requests', 'longtext'),
        _f('status', 'Status', 'choice', options: ['Confirmed', 'Seated', 'Finished', 'Cancelled', 'No-show'], manager: true),
        _f('occasion', 'Occasion', 'choice', options: ['Birthday', 'Anniversary', 'Business', 'Date night', 'Other']), _f('deposit', 'Deposit', 'money', manager: true),
      ]),
      _hours,
      _t('closures', 'Closed days', 'Days we are closed (holidays, private hire): no bookings then', 'see', [
        _f('reason', 'Closed for', 'text', req: true), _f('date', 'Date', 'date', req: true), _f('until', 'Until (for several days)', 'date'),
      ]),
      _t('vouchers', 'Gift vouchers', 'Gift vouchers people buy for someone', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('amount', 'Amount', 'money', req: true),
        _f('recipient', 'Who it’s for', 'text'), _f('message', 'Message for them', 'longtext'),
        _f('code', 'Voucher code', 'text', manager: true), _f('status', 'Status', 'choice', options: ['Requested', 'Paid', 'Sent', 'Redeemed', 'Cancelled'], manager: true),
      ]),
      _t('private_events', 'Private dining', 'Parties and private dining enquiries', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('date', 'Date', 'date', req: true), _f('guests', 'Guests', 'number', req: true),
        _f('event_type', 'Occasion', 'choice', options: ['Birthday', 'Corporate', 'Wedding', 'Anniversary', 'Other'], req: true), _f('notes', 'Tell us more', 'longtext'),
        _f('status', 'Status', 'choice', options: ['Enquiry', 'Confirmed', 'Deposit paid', 'Cancelled'], manager: true),
      ]),
      _t('reviews', 'Reviews', 'What guests say (you choose which to show)', 'see', [
        _f('name', 'Name', 'text', req: true), _f('rating', 'Stars', 'number'), _f('quote', 'Review', 'longtext', req: true), _f('source', 'Where', 'text'),
      ]),
    ],
    'pages': [
      {'id': 'home', 'title': 'Home', 'blocks': [
        _hero('Real Neapolitan cooking, right by the harbour', 'Wood-fired pizza, fresh pasta made every morning and a warm welcome.', button: 'Order now', link: 'order'),
        _features('Why guests come back', [
          'Wood-fired oven: Pizzas baked in ninety seconds at 450°, the Naples way.',
          'Pasta made every morning: Rolled and cut by hand before we open.',
          'Small Italian growers: Wine, olive oil and cheese from families we know.',
          'Delivery & collection: Order online and pick it up hot, or have it brought to you.',
        ]),
        {..._list('menu_items', 'Guest favourites', search: false), 'only': 'popular'},
        {'type': 'testimonials', 'table': 'reviews', 'title': 'What our guests say'},
        _info('opening_hours', 'Visit us'),
        {'type': 'contact', 'title': 'Find us', 'text': 'Two minutes from the harbour car park. Step-free entrance and a heated terrace.'},
      ]},
      {'id': 'menu', 'title': 'Menu', 'blocks': [
        _hero('Our menu', 'Seasonal, simple and made here. Tell us about any allergy and the kitchen will look after you.'),
        {..._list('menu_items', 'Menu'), 'layout': 'menu'},
      ]},
      {'id': 'order', 'title': 'Order', 'blocks': [
        _hero('Order online', 'Pick your dishes, then collect them, have them delivered, or eat in and we’ll bring them to your table.'),
        _list('menu_items', 'Menu'), _form('orders', 'Your order', 'Send to the kitchen', 'Thank you! The kitchen has your order and it will be with you shortly.'),
      ]},
      {'id': 'book', 'title': 'Book a table', 'blocks': [
        _hero('Book a table', 'Pick a day and time, see which tables are free, and it’s yours.'),
        {'type': 'availability', 'table': 'reservations', 'title': 'Find a free table'},
        _form('reservations', 'Your booking', 'Book this table', 'Your table is booked — we look forward to seeing you!'),
      ]},
      {'id': 'private_dining', 'title': 'Private dining', 'blocks': [
        {..._hero('Private dining & parties', 'Birthdays, team dinners and family celebrations: the whole terrace or our private room for up to 30.'), 'image': 'unsplash:1517248135467-4c7edcad34c4'},
        _features('How it works', [
          'Your own space: The private room seats 30, the terrace 40.',
          'A menu for the day: Sharing feasts from £35 a head, built with the chef.',
          'Everything arranged: Cake, flowers, a playlist: just ask.',
        ]),
        {'type': 'gallery', 'table': 'menu_items', 'title': 'From our kitchen'},
        _form('private_events', 'Tell us about your event', 'Send enquiry', 'Thank you! We’ll call you within a day to plan it together.'),
      ]},
      {'id': 'vouchers', 'title': 'Gift vouchers', 'blocks': [
        _hero('Give a dinner to remember', 'A Trattoria Bella gift voucher: for any amount, valid for a year, on food and wine.'),
        _features('Good to know', [
          'Any amount: From £20, spent over one visit or several.',
          'Valid for 12 months: Lunch, dinner, takeaway or delivery.',
          'Sent your way: We text the code to you, ready to print or forward.',
        ]),
        _form('vouchers', 'Buy a gift voucher', 'Request voucher', 'Thank you! We’ll call to take payment and then text you the voucher code.'),
      ]},
      {'id': 'contact', 'title': 'Contact', 'blocks': [
        _hero('Come and see us', 'Lunch and dinner from Tuesday to Sunday. Call us, drop in, or book a table online.'),
        {'type': 'contact', 'title': 'Contact & directions'},
        _info('opening_hours', 'Opening hours'),
        _list('closures', 'Days we are closed', search: false),
      ]},
    ],
  }, {
    'menu_items': [
      {'name': 'Burrata & heritage tomatoes', 'category': 'Starters', 'description': 'Creamy Puglian burrata, sweet tomatoes, basil oil and sea salt.', 'price': 9.5, 'vegetarian': true, 'allergens': 'Milk', 'gluten_free': true},
      {'name': 'Fritto misto', 'category': 'Starters', 'description': 'Crispy squid, prawns and courgette with lemon aioli.', 'price': 11, 'allergens': 'Gluten, molluscs, crustaceans, egg'},
      {'photo': 'unsplash:1574071318508-1cdbab80d002', 'name': 'Margherita', 'category': 'Pizza', 'description': 'San Marzano tomato, fior di latte, basil, extra-virgin olive oil.', 'price': 10.5, 'vegetarian': true, 'allergens': 'Gluten, milk', 'popular': true},
      {'photo': 'unsplash:1565299624946-b28f40a0ae38', 'name': 'Diavola', 'category': 'Pizza', 'description': 'Tomato, mozzarella, spicy salami, chilli honey.', 'price': 13, 'spicy': true, 'allergens': 'Gluten, milk', 'popular': true},
      {'photo': 'unsplash:1513104890138-7c749659a591', 'name': 'Tartufo', 'category': 'Pizza', 'description': 'White base, mushrooms, black truffle cream, rocket.', 'price': 15, 'vegetarian': true, 'allergens': 'Gluten, milk'},
      {'photo': 'unsplash:1621996346565-e3dbc646d9a9', 'name': 'Cacio e pepe', 'category': 'Pasta', 'description': 'Tonnarelli, pecorino romano, toasted black pepper.', 'price': 12.5, 'vegetarian': true, 'allergens': 'Gluten, egg, milk', 'popular': true},
      {'photo': 'unsplash:1551183053-bf91a1d81141', 'name': 'Linguine allo scoglio', 'category': 'Pasta', 'description': 'Mussels, clams, prawns, cherry tomato and white wine.', 'price': 18, 'allergens': 'Gluten, molluscs, crustaceans, sulphites'},
      {'photo': 'unsplash:1571877227200-a0d98ea607e9', 'name': 'Tiramisù', 'category': 'Desserts', 'description': 'Our nonna’s recipe, made fresh every day.', 'price': 7, 'vegetarian': true, 'allergens': 'Gluten, egg, milk', 'popular': true},
      {'name': 'Limoncello sorbet', 'category': 'Desserts', 'description': 'Light, zesty and refreshing.', 'price': 6, 'vegetarian': true, 'vegan': true, 'gluten_free': true},
      {'name': 'Aperol spritz', 'category': 'Drinks', 'description': 'Aperol, prosecco, soda and orange.', 'price': 9, 'vegan': true, 'gluten_free': true, 'allergens': 'Sulphites'},
      {'name': 'San Pellegrino', 'category': 'Drinks', 'description': 'Sparkling mineral water, 750 ml.', 'price': 4, 'vegan': true, 'gluten_free': true},
      {'name': 'Garlic focaccia', 'category': 'Sides', 'description': 'Rosemary, sea salt and roasted garlic, warm from the oven.', 'price': 5, 'vegetarian': true, 'vegan': true, 'allergens': 'Gluten'},
      {'name': 'Rocket & parmesan salad', 'category': 'Sides', 'description': 'Wild rocket, aged parmesan, lemon and olive oil.', 'price': 5.5, 'vegetarian': true, 'gluten_free': true, 'allergens': 'Milk'},
      {'name': 'Rosemary potatoes', 'category': 'Sides', 'description': 'Crisp roast potatoes with rosemary and garlic.', 'price': 4.5, 'vegetarian': true, 'vegan': true, 'gluten_free': true},
    ],
    'dining_tables': [
      {'number': '1', 'seats': 2, 'area': 'Window'}, {'number': '2', 'seats': 2, 'area': 'Window'}, {'number': '3', 'seats': 4, 'area': 'Inside'},
      {'number': '4', 'seats': 4, 'area': 'Inside'}, {'number': '5', 'seats': 6, 'area': 'Inside'}, {'number': '6', 'seats': 4, 'area': 'Terrace'}, {'number': '7', 'seats': 8, 'area': 'Terrace'},
    ],
    'opening_hours': [{'opens': '12:00', 'closes': '22:30', 'days': 'Tuesday – Sunday'}],
    'closures': [
      {'reason': 'Christmas', 'date': '2026-12-25', 'until': '2026-12-26'},
      {'reason': 'New Year’s Day', 'date': '2027-01-01'},
    ],
    'reviews': [
      {'name': 'Sophie M.', 'rating': 5, 'quote': 'The best pizza outside Naples. The Diavola with chilli honey is unreal, and the staff remembered our daughter’s birthday.', 'source': 'Google'},
      {'name': 'James O.', 'rating': 5, 'quote': 'Booked online in seconds, table by the window, cacio e pepe done exactly right. We’ll be back next week.', 'source': 'Tripadvisor'},
      {'name': 'Priya K.', 'rating': 4, 'quote': 'Lovely terrace, fresh pasta and a proper tiramisù. Delivery arrived hot too.', 'source': 'Google'},
    ],
  }),

  AppTemplate('salon', 'Hair & beauty salon', 'Services and prices, your team, and online appointment requests.', {
    'name': 'Studio Lumière',
    'summary': 'Clients see services and stylists and book an appointment.',
    'site': {'style': 'elegant', 'tagline': 'Hair, colour & care', 'hero': 'unsplash:1560066984-138dadb4c035', 'about': 'A calm, light-filled studio where every appointment starts with a proper consultation.', 'address': '48 King’s Road', 'phone': '020 7946 0456', 'currency': '£'},
    'tables': [
      _t('services', 'Services', 'Treatments and prices', 'see', [
        _f('name', 'Service', 'text', req: true), _f('category', 'Category', 'choice', options: ['Cut & style', 'Colour', 'Treatments', 'Nails']),
        _f('description', 'Description', 'longtext'), _f('duration', 'Minutes', 'number'), _f('price', 'Price', 'money'), _f('photo', 'Photo', 'image'),
      ]),
      _t('stylists', 'Our team', 'Stylists and specialists', 'see', [_f('name', 'Name', 'text', req: true), _f('role', 'Speciality', 'text'), _f('bio', 'About', 'longtext'), _f('photo', 'Photo', 'image')]),
      _t('appointments', 'Appointments', 'Appointment requests', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('service', 'Service', 'link', link: 'services', req: true),
        _f('stylist', 'Stylist', 'link', link: 'stylists'), _f('date', 'Date', 'date', req: true), _f('time', 'Time', 'time', req: true), _f('notes', 'Anything we should know?', 'longtext'),
        _f('status', 'Status', 'choice', options: ['Confirmed', 'Done', 'Cancelled', 'No-show'], manager: true),
      ]),
      _hours,
    ],
    'pages': [
      {'id': 'home', 'title': 'Home', 'blocks': [_hero('Look and feel your best', 'Expert cuts, beautiful colour and treatments that leave your hair healthier.', button: 'Book now', link: 'book'), _list('services', 'Services & prices'), _info('opening_hours', 'Opening hours')]},
      {'id': 'team', 'title': 'Our team', 'blocks': [_hero('Meet the team', 'Experienced, friendly and always learning.'), _list('stylists', 'Stylists', search: false)]},
      {'id': 'book', 'title': 'Book', 'blocks': [
        _hero('Book an appointment', 'See who’s free, pick a time, and you’re booked.'),
        {'type': 'availability', 'table': 'appointments', 'title': 'Find a free stylist'},
        _form('appointments', 'Your appointment', 'Book appointment', 'You’re booked! We’ll text you a reminder the day before.'),
      ]},
    ],
  }, {
    'services': [
      {'photo': 'unsplash:1522337360788-8b13dee7a37e', 'name': 'Women’s cut & blow-dry', 'category': 'Cut & style', 'description': 'Consultation, wash, precision cut and finish.', 'duration': 60, 'price': 58},
      {'name': 'Men’s cut', 'category': 'Cut & style', 'description': 'Wash, cut and style.', 'duration': 30, 'price': 32},
      {'photo': 'unsplash:1562322140-8baeececf3df', 'name': 'Blow-dry', 'category': 'Cut & style', 'description': 'Smooth, bouncy or beach waves.', 'duration': 45, 'price': 35},
      {'name': 'Full head colour', 'category': 'Colour', 'description': 'Rich, even colour from root to tip.', 'duration': 120, 'price': 95},
      {'name': 'Balayage', 'category': 'Colour', 'description': 'Hand-painted, sun-kissed lightness.', 'duration': 180, 'price': 160},
      {'name': 'Olaplex treatment', 'category': 'Treatments', 'description': 'Repairs and strengthens damaged hair.', 'duration': 30, 'price': 30},
      {'name': 'Gel manicure', 'category': 'Nails', 'description': 'Long-lasting colour with a glossy finish.', 'duration': 45, 'price': 28},
    ],
    'stylists': [
      {'name': 'Amélie', 'role': 'Creative director · colour', 'bio': 'Fifteen years of colour work in Paris and London.'},
      {'name': 'Marcus', 'role': 'Senior stylist · cuts', 'bio': 'Precision cutting and men’s grooming.'},
      {'name': 'Priya', 'role': 'Stylist · curly hair', 'bio': 'Curl specialist; every texture welcome.'},
    ],
    'opening_hours': [{'opens': '09:00', 'closes': '19:00', 'days': 'Monday – Saturday'}],
  }),

  AppTemplate('barber', 'Barber shop', 'Cuts and prices, your barbers, and booking a chair at a time that’s free.', {
    'name': 'Kings Cut Barbers',
    'summary': 'Clients see cuts and prices, pick a barber and book a free time.',
    'site': {'style': 'bold', 'tagline': 'Sharp fades, classic cuts, hot towel shaves', 'hero': 'unsplash:1503951914875-452162b0f3f1', 'about': 'A proper neighbourhood barber: walk-ins welcome, bookings guaranteed, and the kettle is always on.', 'address': '7 Market Lane', 'phone': '020 7946 0789', 'currency': '£', 'booking_minutes': '30'},
    'tables': [
      _t('services', 'Cuts & prices', 'Haircuts, beard work and prices', 'see', [
        _f('name', 'Service', 'text', req: true), _f('category', 'Category', 'choice', options: ['Haircuts', 'Beard', 'Shaves', 'Kids']),
        _f('description', 'Description', 'longtext'), _f('duration', 'Minutes', 'number'), _f('price', 'Price', 'money'),
      ]),
      _t('barbers', 'Our barbers', 'The barbers', 'see', [_f('name', 'Name', 'text', req: true), _f('speciality', 'Speciality', 'text'), _f('bio', 'About', 'longtext'), _f('photo', 'Photo', 'image')]),
      _t('appointments', 'Appointments', 'Booked chairs', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('service', 'Service', 'link', link: 'services', req: true),
        _f('barber', 'Barber', 'link', link: 'barbers'), _f('date', 'Date', 'date', req: true), _f('time', 'Time', 'time', req: true), _f('notes', 'Anything we should know?', 'longtext'),
        _f('status', 'Status', 'choice', options: ['Booked', 'Done', 'Cancelled', 'No-show'], manager: true),
      ]),
      _hours,
    ],
    'pages': [
      {'id': 'home', 'title': 'Home', 'blocks': [_hero('Look sharp', 'Fades, scissor cuts, beard trims and hot towel shaves by barbers who care.', button: 'Book a chair', link: 'book'), _list('services', 'Cuts & prices'), _info('opening_hours', 'Opening hours')]},
      {'id': 'team', 'title': 'Barbers', 'blocks': [_hero('Meet the barbers', 'Pick your favourite or take whoever is free.'), _list('barbers', 'Barbers', search: false)]},
      {'id': 'book', 'title': 'Book', 'blocks': [
        _hero('Book a chair', 'See which barber is free, pick a time, and you’re in.'),
        {'type': 'availability', 'table': 'appointments', 'title': 'Find a free barber'},
        _form('appointments', 'Your appointment', 'Book my chair', 'You’re booked! See you soon.'),
      ]},
    ],
  }, {
    'services': [
      {'name': 'Skin fade', 'category': 'Haircuts', 'description': 'Clean skin fade blended into any length on top.', 'duration': 30, 'price': 22},
      {'name': 'Classic cut', 'category': 'Haircuts', 'description': 'Scissor or clipper cut, wash and style.', 'duration': 30, 'price': 18},
      {'name': 'Buzz cut', 'category': 'Haircuts', 'description': 'One length all over.', 'duration': 15, 'price': 12},
      {'name': 'Beard trim', 'category': 'Beard', 'description': 'Shape-up with clippers, razor line and beard oil.', 'duration': 15, 'price': 10},
      {'name': 'Cut & beard', 'category': 'Beard', 'description': 'Any haircut plus a full beard trim.', 'duration': 45, 'price': 28},
      {'name': 'Hot towel shave', 'category': 'Shaves', 'description': 'Traditional straight-razor shave with hot towels.', 'duration': 30, 'price': 20},
      {'name': 'Kids cut', 'category': 'Kids', 'description': 'Under 12s.', 'duration': 20, 'price': 12},
    ],
    'barbers': [
      {'name': 'Tony', 'speciality': 'Fades & skin fades', 'bio': 'Twenty years behind the chair.'},
      {'name': 'Jay', 'speciality': 'Beards & hot towel shaves', 'bio': 'Razor work and beard sculpting.'},
      {'name': 'Ali', 'speciality': 'Classic scissor cuts', 'bio': 'Old-school cuts, done properly.'},
    ],
    'opening_hours': [{'opens': '09:00', 'closes': '19:00', 'days': 'Monday – Saturday'}],
  }),

  AppTemplate('gym', 'Gym & fitness classes', 'Class timetable, trainers, memberships and class sign-ups.', {
    'name': 'Forge Fitness',
    'summary': 'Members see classes and sign up; the manager runs the timetable.',
    'site': {'style': 'bold', 'tagline': 'Stronger every week', 'hero': 'unsplash:1534438327276-14e5300c3a48', 'about': 'Strength, conditioning and community. Coached classes for every level, seven days a week.', 'address': 'Unit 4, Canal Works', 'phone': '0161 496 0789', 'currency': '£'},
    'tables': [
      _t('classes', 'Classes', 'Weekly class timetable', 'see', [
        _f('name', 'Class', 'text', req: true), _f('day', 'Day', 'choice', options: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']),
        _f('time', 'Time', 'time'), _f('level', 'Level', 'choice', options: ['All levels', 'Beginner', 'Advanced']), _f('trainer', 'Trainer', 'link', link: 'trainers'),
        _f('description', 'About', 'longtext'), _f('spots', 'Spots', 'number'), _f('photo', 'Photo', 'image'),
      ]),
      _t('trainers', 'Trainers', 'Coaches', 'see', [_f('name', 'Name', 'text', req: true), _f('speciality', 'Speciality', 'text'), _f('bio', 'About', 'longtext'), _f('photo', 'Photo', 'image')]),
      _t('memberships', 'Memberships', 'Plans and prices', 'see', [_f('name', 'Plan', 'text', req: true), _f('description', 'What you get', 'longtext'), _f('price', 'Price per month', 'money')]),
      _t('signups', 'Sign-ups', 'Class bookings', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('email', 'Email', 'email'), _f('class', 'Class', 'link', link: 'classes', req: true), _f('date', 'Date', 'date', req: true),
        _f('status', 'Status', 'choice', options: ['Booked', 'Attended', 'No-show', 'Cancelled'], manager: true),
      ]),
    ],
    'pages': [
      {'id': 'home', 'title': 'Home', 'blocks': [_hero('Train hard. Feel unstoppable.', 'Coached classes for every level, in a gym that feels like a team.', button: 'Book a class', link: 'classes'), _list('memberships', 'Memberships', search: false)]},
      {'id': 'classes', 'title': 'Classes', 'blocks': [_hero('This week’s classes', 'Find your class and save your spot.'), _list('classes', 'Timetable'), _form('signups', 'Save my spot', 'Book my place', 'You’re in! See you in class.')]},
      {'id': 'trainers', 'title': 'Trainers', 'blocks': [_hero('Your coaches', 'Qualified, motivating and here for you.'), _list('trainers', 'Trainers', search: false)]},
    ],
  }, {
    'trainers': [
      {'name': 'Jade', 'speciality': 'Strength & Olympic lifting', 'bio': 'Former GB weightlifter. Loves a heavy deadlift.'},
      {'name': 'Tom', 'speciality': 'HIIT & conditioning', 'bio': 'Makes 45 minutes feel like 20.'},
      {'name': 'Sofia', 'speciality': 'Yoga & mobility', 'bio': 'Helps lifters move better and recover faster.'},
    ],
    'classes': [
      {'name': 'Barbell strength', 'day': 'Monday', 'time': '18:30', 'level': 'All levels', 'trainer': 'Jade', 'description': 'Squat, press and pull with expert coaching.', 'spots': 14},
      {'photo': 'unsplash:1518611012118-696072aa579a', 'name': 'HIIT blast', 'day': 'Tuesday', 'time': '07:00', 'level': 'All levels', 'trainer': 'Tom', 'description': 'Intervals that build fitness fast.', 'spots': 20},
      {'photo': 'unsplash:1571019613454-1cb2f99b2d8b', 'name': 'Mobility flow', 'day': 'Wednesday', 'time': '19:00', 'level': 'Beginner', 'trainer': 'Sofia', 'description': 'Stretch, breathe and move freely.', 'spots': 16},
      {'name': 'Olympic lifting', 'day': 'Thursday', 'time': '18:30', 'level': 'Advanced', 'trainer': 'Jade', 'description': 'Snatch and clean & jerk technique.', 'spots': 10},
      {'name': 'Saturday sweat', 'day': 'Saturday', 'time': '09:00', 'level': 'All levels', 'trainer': 'Tom', 'description': 'Team workout to start the weekend.', 'spots': 24},
    ],
    'memberships': [
      {'name': 'Off-peak', 'description': 'Gym access 10:00–16:00 and weekends.', 'price': 25},
      {'name': 'Unlimited', 'description': 'Gym any time plus every class.', 'price': 45},
      {'name': 'Class pass', 'description': '10 classes to use within three months.', 'price': 80},
    ],
  }),

  AppTemplate('shop', 'Shop · online orders', 'Product catalogue with photos and stock; orders to collect or delivered to your door.', {
    'name': 'Corner Store',
    'summary': 'Customers browse products and order to collect or for delivery.',
    'site': {'style': 'modern', 'tagline': 'Order online, collect in minutes', 'hero': 'unsplash:1542838132-92c53300491e', 'about': 'Your local shop for fresh bread, groceries and everyday essentials.', 'address': '3 Market Square', 'phone': '0117 496 0321', 'currency': '£'},
    'tables': [
      _t('products', 'Products', 'Things for sale', 'see', [
        _f('name', 'Product', 'text', req: true), _f('category', 'Category', 'choice', options: ['Bakery', 'Fresh', 'Pantry', 'Drinks', 'Household']),
        _f('description', 'Description', 'longtext'), _f('price', 'Price', 'money', req: true), _f('photo', 'Photo', 'image'), _f('in_stock', 'In stock', 'yesno'),
      ]),
      _t('orders', 'Orders', 'Orders to collect or deliver', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('items', 'Your basket', 'links', link: 'products', qty: true, req: true),
        _f('type', 'Collect or deliver', 'choice', options: ['Collection', 'Delivery'], req: true),
        _f('address', 'Delivery address', 'text', req: true, when: {'type': ['Delivery']}), _f('postcode', 'Postcode', 'text', req: true, when: {'type': ['Delivery']}),
        _f('pickup', 'Collect / deliver at', 'datetime', req: true), _f('notes', 'Notes', 'longtext'),
        _f('status', 'Status', 'choice', options: ['New', 'Packing', 'Ready', 'Out for delivery', 'Collected', 'Delivered', 'Cancelled'], manager: true),
      ]),
      _hours,
    ],
    'pages': [
      {'id': 'home', 'title': 'Shop', 'blocks': [_hero('Fresh, local and ready when you are', 'Order online: collect in minutes or have it delivered.', button: 'Start your order', link: 'order'), _list('products', 'Products'), _info('opening_hours', 'Opening hours')]},
      {'id': 'order', 'title': 'Order', 'blocks': [_hero('Order online', 'Add products, choose collection or delivery and a time, and we’ll have it packed.'), _list('products', 'Products'), _form('orders', 'Your basket', 'Place order', 'Thank you! We’ll text you when your order is ready.')]},
    ],
  }, {
    'products': [
      {'photo': 'unsplash:1509440159596-0249088772ff', 'name': 'Sourdough loaf', 'category': 'Bakery', 'description': 'Baked this morning, 800 g.', 'price': 4.2, 'in_stock': true},
      {'photo': 'unsplash:1555507036-ab1f4038808a', 'name': 'Butter croissant', 'category': 'Bakery', 'description': 'Flaky, all-butter.', 'price': 1.8, 'in_stock': true},
      {'name': 'Free-range eggs (6)', 'category': 'Fresh', 'description': 'From a farm ten miles away.', 'price': 2.6, 'in_stock': true},
      {'photo': 'unsplash:1542838132-92c53300491e', 'name': 'Seasonal veg box', 'category': 'Fresh', 'description': 'A week of local vegetables.', 'price': 14, 'in_stock': true},
      {'name': 'Extra-virgin olive oil', 'category': 'Pantry', 'description': 'Cold-pressed, 500 ml.', 'price': 8.5, 'in_stock': true},
      {'photo': 'unsplash:1495474472287-4d71bcdd2085', 'name': 'Ground coffee', 'category': 'Pantry', 'description': 'Medium roast, 250 g.', 'price': 6.4, 'in_stock': true},
      {'name': 'Sparkling lemonade', 'category': 'Drinks', 'description': 'Cloudy and real, 750 ml.', 'price': 2.9, 'in_stock': true},
      {'name': 'Eco washing-up liquid', 'category': 'Household', 'description': 'Refillable bottle.', 'price': 3.2, 'in_stock': false},
    ],
    'opening_hours': [{'opens': '07:00', 'closes': '21:00', 'days': 'Every day'}],
  }),

  AppTemplate('clinic', 'Clinic · appointments', 'Treatments, doctors and appointment requests from patients.', {
    'name': 'Riverside Dental',
    'summary': 'Patients see treatments and doctors and request an appointment.',
    'site': {'style': 'fresh', 'tagline': 'Gentle, modern dental care', 'hero': 'unsplash:1629909613654-28e377c37b09', 'about': 'Family dentistry with the latest technology and a calm, unhurried approach.', 'address': '27 River Lane', 'phone': '0131 496 0654', 'email': 'hello@riverside.example', 'currency': '£'},
    'tables': [
      _t('treatments', 'Treatments', 'What you offer', 'see', [_f('name', 'Treatment', 'text', req: true), _f('description', 'Description', 'longtext'), _f('duration', 'Minutes', 'number'), _f('price', 'From', 'money')]),
      _t('doctors', 'Our dentists', 'Doctors and hygienists', 'see', [_f('name', 'Name', 'text', req: true), _f('role', 'Role', 'text'), _f('bio', 'About', 'longtext'), _f('photo', 'Photo', 'image')]),
      _t('appointments', 'Appointments', 'Appointment requests', 'add', [
        _f('name', 'Patient name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('email', 'Email', 'email'),
        _f('treatment', 'Treatment', 'link', link: 'treatments', req: true), _f('doctor', 'Preferred dentist', 'link', link: 'doctors'),
        _f('date', 'Date', 'date', req: true), _f('time', 'Time', 'time', req: true), _f('reason', 'Reason for visit', 'longtext'),
        _f('status', 'Status', 'choice', options: ['Confirmed', 'Completed', 'Cancelled', 'No-show'], manager: true),
      ]),
      _hours,
    ],
    'pages': [
      {'id': 'home', 'title': 'Home', 'blocks': [_hero('Healthy smiles, without the worry', 'Friendly dentists, clear prices and appointments that suit you.', button: 'Request an appointment', link: 'book'), _list('treatments', 'Treatments'), _info('opening_hours', 'Opening hours')]},
      {'id': 'team', 'title': 'Our dentists', 'blocks': [_hero('Meet our team', 'Experienced, gentle and here to help.'), _list('doctors', 'Dentists', search: false)]},
      {'id': 'book', 'title': 'Appointments', 'blocks': [
        _hero('Book an appointment', 'Choose a day and see when our dentists are free.'),
        {'type': 'availability', 'table': 'appointments', 'title': 'Find a free appointment'},
        _form('appointments', 'Your appointment', 'Book appointment', 'You’re booked! We’ll send a reminder the day before.'),
      ]},
    ],
  }, {
    'treatments': [
      {'name': 'Check-up & clean', 'description': 'Full examination, scale and polish.', 'duration': 40, 'price': 65},
      {'name': 'Teeth whitening', 'description': 'Professional at-home whitening kit with custom trays.', 'duration': 30, 'price': 299},
      {'name': 'White filling', 'description': 'Natural-looking, tooth-coloured fillings.', 'duration': 45, 'price': 120},
      {'name': 'Invisalign consultation', 'description': 'Scan, plan and price for clear aligners.', 'duration': 30, 'price': 0},
      {'name': 'Emergency appointment', 'description': 'Same-day help for pain or damage.', 'duration': 30, 'price': 85},
    ],
    'doctors': [
      {'name': 'Dr Hannah Reid', 'role': 'Principal dentist', 'bio': 'Special interest in nervous patients and cosmetic dentistry.'},
      {'photo': 'unsplash:1588776814546-1ffcf47267a5', 'name': 'Dr Omar Khalil', 'role': 'Dentist · implants', 'bio': 'Implant and restorative work with a gentle touch.'},
      {'name': 'Leah Grant', 'role': 'Hygienist', 'bio': 'Helps you keep your gums healthy for life.'},
    ],
    'opening_hours': [{'opens': '08:30', 'closes': '18:00', 'days': 'Monday – Friday'}],
  }),

  AppTemplate('hotel', 'Hotel · guesthouse', 'Rooms with photos and prices, and booking requests.', {
    'name': 'The Harbour House',
    'summary': 'Guests see rooms and request a stay.',
    'site': {'style': 'minimal', 'tagline': 'Eight rooms by the sea', 'hero': 'unsplash:1566073771259-6a8506099945', 'about': 'A small boutique guesthouse with sea views, local breakfasts and the beach two minutes away.', 'address': '1 Quay Road, St Ives', 'phone': '01736 496 0987', 'email': 'stay@harbourhouse.example', 'currency': '£'},
    'tables': [
      _t('rooms', 'Rooms', 'Rooms and nightly prices', 'see', [
        _f('name', 'Room', 'text', req: true), _f('description', 'Description', 'longtext'), _f('guests', 'Sleeps up to', 'number'), _f('bed', 'Bed', 'choice', options: ['Double', 'King', 'Twin', 'Family']),
        _f('price', 'Per night', 'money'), _f('sea_view', 'Sea view', 'yesno'), _f('photo', 'Photo', 'image'),
      ]),
      _t('bookings', 'Bookings', 'Booking requests', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('email', 'Email', 'email'), _f('room', 'Room', 'link', link: 'rooms', req: true),
        _f('check_in', 'Check-in', 'date', req: true), _f('check_out', 'Check-out', 'date', req: true), _f('guests', 'Guests', 'number', req: true), _f('requests', 'Requests', 'longtext'),
        _f('status', 'Status', 'choice', options: ['Requested', 'Confirmed', 'Checked in', 'Cancelled'], manager: true),
      ]),
    ],
    'pages': [
      {'id': 'home', 'title': 'Home', 'blocks': [_hero('Wake up to the sea', 'Eight calm, light rooms a short walk from the beach.', button: 'Check availability', link: 'book'), _text('## A small hotel with a big welcome\nLocal breakfasts, sea air and quiet nights. Everything you need, nothing you don’t.'), _list('rooms', 'Rooms', search: false)]},
      {'id': 'book', 'title': 'Book', 'blocks': [_hero('Book your stay', 'Choose a room and your dates; we’ll confirm by email.'), _form('bookings', 'Your stay', 'Request booking', 'Thank you! We’ll email you to confirm your stay.')]},
    ],
  }, {
    'rooms': [
      {'photo': 'unsplash:1590490360182-c33d57733427', 'name': 'Harbour View', 'description': 'Our favourite: a king bed facing the boats and lighthouse.', 'guests': 2, 'bed': 'King', 'price': 165, 'sea_view': true},
      {'photo': 'unsplash:1611892440504-42a792e24d32', 'name': 'The Loft', 'description': 'Top-floor room with sloping ceilings and a roll-top bath.', 'guests': 2, 'bed': 'Double', 'price': 145, 'sea_view': true},
      {'name': 'Garden Twin', 'description': 'Quiet twin room opening onto the garden.', 'guests': 2, 'bed': 'Twin', 'price': 115},
      {'name': 'Family Suite', 'description': 'Two connecting rooms for up to four.', 'guests': 4, 'bed': 'Family', 'price': 210, 'sea_view': true},
    ],
  }),

  AppTemplate('garage', 'Car repair garage', 'Services with prices and service bookings with car details.', {
    'name': 'Precision Motors',
    'summary': 'Drivers see services and book their car in.',
    'site': {'style': 'modern', 'tagline': 'Honest servicing & repairs', 'hero': 'unsplash:1486262715619-67b85e0b08d3', 'about': 'Independent garage with main-dealer skills and fair, fixed prices.', 'address': 'Unit 9, Riverside Industrial Estate', 'phone': '0113 496 0246', 'currency': '£'},
    'tables': [
      _t('services', 'Services', 'Work and prices', 'see', [_f('name', 'Service', 'text', req: true), _f('description', 'What’s included', 'longtext'), _f('price', 'From', 'money'), _f('time', 'Takes', 'text')]),
      _t('bookings', 'Bookings', 'Cars booked in', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('car', 'Car (make & model)', 'text', req: true), _f('plate', 'Registration', 'text', req: true),
        _f('services', 'Services', 'links', link: 'services', req: true), _f('date', 'Drop-off date', 'date', req: true), _f('notes', 'Describe the problem', 'longtext'),
        _f('status', 'Status', 'choice', options: ['Booked', 'In the workshop', 'Ready', 'Collected', 'Cancelled'], manager: true),
      ]),
      _hours,
    ],
    'pages': [
      {'id': 'home', 'title': 'Home', 'blocks': [_hero('Expert car care at fair prices', 'Servicing, MOT and repairs for every make — with no surprises on the bill.', button: 'Book your car in', link: 'book'), _list('services', 'Services & prices'), _info('opening_hours', 'Opening hours')]},
      {'id': 'book', 'title': 'Book', 'blocks': [_hero('Book your car in', 'Tell us about your car and pick a day. We’ll call with a quote before any extra work.'), _form('bookings', 'Booking', 'Book in', 'Thank you! We’ll call to confirm your booking.')]},
    ],
  }, {
    'services': [
      {'name': 'MOT test', 'description': 'Full MOT with free retest within 10 days.', 'price': 54.85, 'time': '1 hour'},
      {'name': 'Interim service', 'description': 'Oil and filter, 30-point check.', 'price': 129, 'time': '1.5 hours'},
      {'name': 'Full service', 'description': 'All filters, plugs, fluids and 60-point check.', 'price': 229, 'time': '3 hours'},
      {'name': 'Brake pads (front)', 'description': 'Quality pads fitted and tested.', 'price': 140, 'time': '1.5 hours'},
      {'name': 'Air-con re-gas', 'description': 'Leak test and re-gas.', 'price': 69, 'time': '45 minutes'},
      {'name': 'Diagnostics', 'description': 'Find that warning light’s cause.', 'price': 45, 'time': '30 minutes'},
    ],
    'opening_hours': [{'opens': '08:00', 'closes': '17:30', 'days': 'Monday – Friday, Saturday mornings'}],
  }),

  AppTemplate('tutoring', 'Tutoring & courses', 'Courses with level and schedule, and student enrolments.', {
    'name': 'Bright Minds Tutoring',
    'summary': 'Parents and students see courses and enrol.',
    'site': {'style': 'fresh', 'tagline': 'Confidence in every subject', 'hero': 'unsplash:1503676260728-1c00da094a0b', 'about': 'Small-group and one-to-one tutoring from qualified teachers.', 'email': 'hello@brightminds.example', 'phone': '020 7946 0777', 'currency': '£'},
    'tables': [
      _t('courses', 'Courses', 'Courses on offer', 'see', [
        _f('name', 'Course', 'text', req: true), _f('subject', 'Subject', 'choice', options: ['Maths', 'English', 'Science', 'Languages', 'Coding']),
        _f('level', 'Level', 'choice', options: ['Primary', 'GCSE', 'A-level', 'Adults']), _f('schedule', 'When', 'text'), _f('description', 'About', 'longtext'), _f('price', 'Per term', 'money'), _f('photo', 'Photo', 'image'),
      ]),
      _t('enrolments', 'Enrolments', 'Students who signed up', 'add', [
        _f('student', 'Student name', 'text', req: true), _f('parent', 'Parent / guardian', 'text'), _f('phone', 'Phone', 'phone', req: true), _f('email', 'Email', 'email'),
        _f('course', 'Course', 'link', link: 'courses', req: true), _f('notes', 'Anything we should know?', 'longtext'), _f('status', 'Status', 'choice', options: ['New', 'Confirmed', 'Waiting list', 'Cancelled'], manager: true),
      ]),
    ],
    'pages': [
      {'id': 'home', 'title': 'Home', 'blocks': [_hero('Learning that clicks', 'Patient, qualified tutors who build real understanding and confidence.', button: 'Enrol now', link: 'enrol'), _list('courses', 'Courses')]},
      {'id': 'enrol', 'title': 'Enrol', 'blocks': [_hero('Enrol a student', 'Choose a course and we’ll be in touch with everything you need.'), _form('enrolments', 'Enrolment', 'Enrol', 'Thank you! We’ll email you the details within a day.')]},
    ],
  }, {
    'courses': [
      {'name': 'GCSE Maths booster', 'subject': 'Maths', 'level': 'GCSE', 'schedule': 'Tuesdays 17:00', 'description': 'Exam technique and the topics that matter most.', 'price': 180},
      {'name': 'A-level Chemistry', 'subject': 'Science', 'level': 'A-level', 'schedule': 'Thursdays 18:00', 'description': 'Organic, physical and inorganic made clear.', 'price': 220},
      {'name': 'Reading confidence', 'subject': 'English', 'level': 'Primary', 'schedule': 'Saturdays 10:00', 'description': 'Phonics and fun with books for ages 6–9.', 'price': 150},
      {'name': 'Python for beginners', 'subject': 'Coding', 'level': 'Adults', 'schedule': 'Wednesdays 19:00', 'description': 'From zero to your first useful programs.', 'price': 200},
      {'name': 'Conversational Spanish', 'subject': 'Languages', 'level': 'Adults', 'schedule': 'Mondays 19:00', 'description': 'Speak from week one in a relaxed group.', 'price': 160},
    ],
  }),

  AppTemplate('events', 'Events & tickets', 'Upcoming events with dates and prices, and ticket requests.', {
    'name': 'Basement Live',
    'summary': 'Fans see upcoming shows and request tickets.',
    'site': {'style': 'bold', 'tagline': 'Live music, every week', 'hero': 'unsplash:1501281668745-f7f57925c3b4', 'about': 'An intimate 200-capacity venue for new bands, jazz nights and DJs.', 'address': '88 Camden Road', 'email': 'tickets@basement.example', 'currency': '£'},
    'tables': [
      _t('events', 'Events', 'Upcoming shows', 'see', [
        _f('name', 'Event', 'text', req: true), _f('date', 'Date', 'date', req: true), _f('time', 'Doors', 'time'), _f('genre', 'Genre', 'choice', options: ['Rock', 'Jazz', 'Electronic', 'Comedy', 'Folk']),
        _f('description', 'About', 'longtext'), _f('price', 'Ticket', 'money'), _f('photo', 'Poster', 'image'), _f('sold_out', 'Sold out', 'yesno'),
      ]),
      _t('tickets', 'Ticket requests', 'Ticket orders', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('email', 'Email', 'email'), _f('event', 'Event', 'link', link: 'events', req: true), _f('quantity', 'Tickets', 'number', req: true),
        _f('status', 'Status', 'choice', options: ['Requested', 'Paid', 'Sent', 'Cancelled'], manager: true),
      ]),
    ],
    'pages': [
      {'id': 'home', 'title': 'What’s on', 'blocks': [_hero('Live music, up close', 'New bands, late-night jazz and the best DJs — every week.', button: 'Get tickets', link: 'tickets'), _list('events', 'Coming up')]},
      {'id': 'tickets', 'title': 'Tickets', 'blocks': [_hero('Get tickets', 'Choose a show and how many tickets; we’ll email you a payment link.'), _form('tickets', 'Ticket request', 'Request tickets', 'Thank you! Check your email for your payment link.')]},
    ],
  }, {
    'events': [
      {'photo': 'unsplash:1492144534655-ae79c964c9d7', 'name': 'The Midnight Owls', 'date': '2026-10-17', 'time': '19:30', 'genre': 'Rock', 'description': 'Loud, sweaty, joyful garage rock.', 'price': 12},
      {'name': 'Late Jazz Session', 'date': '2026-10-22', 'time': '21:00', 'genre': 'Jazz', 'description': 'House trio plus surprise guests.', 'price': 8},
      {'photo': 'unsplash:1501386761578-eac5c94b800a', 'name': 'Deep House Friday', 'date': '2026-10-24', 'time': '22:00', 'genre': 'Electronic', 'description': 'Four DJs, all night long.', 'price': 15},
      {'name': 'Stand-up Showcase', 'date': '2026-10-29', 'time': '20:00', 'genre': 'Comedy', 'description': 'Five rising comics, one great night.', 'price': 10},
    ],
  }),

  AppTemplate('realestate', 'Real estate listings', 'Property listings with photos, and viewing requests.', {
    'name': 'Oak & Stone Estates',
    'summary': 'Buyers and renters browse homes and book viewings.',
    'site': {'style': 'minimal', 'tagline': 'Homes worth coming home to', 'hero': 'unsplash:1600596542815-ffad4c1539a9', 'about': 'Independent estate agents who know every street in town.', 'address': '5 High Street', 'phone': '01865 496 0135', 'email': 'homes@oakstone.example', 'currency': '£'},
    'tables': [
      _t('listings', 'Properties', 'Homes for sale and to rent', 'see', [
        _f('title', 'Property', 'text', req: true), _f('type', 'For', 'choice', options: ['Sale', 'Rent']), _f('price', 'Price', 'money'), _f('bedrooms', 'Bedrooms', 'number'),
        _f('area', 'Area', 'text'), _f('description', 'Description', 'longtext'), _f('photo', 'Photo', 'image'), _f('available', 'Available', 'yesno'),
      ]),
      _t('viewings', 'Viewing requests', 'People who want to see a home', 'add', [
        _f('name', 'Your name', 'text', req: true), _f('phone', 'Phone', 'phone', req: true), _f('email', 'Email', 'email'), _f('property', 'Property', 'link', link: 'listings', req: true),
        _f('date', 'Preferred date', 'date'), _f('message', 'Message', 'longtext'), _f('status', 'Status', 'choice', options: ['New', 'Booked', 'Viewed', 'Offer made', 'Closed'], manager: true),
      ]),
    ],
    'pages': [
      {'id': 'home', 'title': 'Properties', 'blocks': [_hero('Find the place you’ll love', 'Hand-picked homes to buy and rent, and agents who answer the phone.', button: 'Book a viewing', link: 'viewing'), _list('listings', 'Available now')]},
      {'id': 'viewing', 'title': 'Book a viewing', 'blocks': [_hero('Book a viewing', 'Choose a property and a day; we’ll confirm a time.'), _form('viewings', 'Viewing request', 'Request viewing', 'Thank you! An agent will call you today.')]},
    ],
  }, {
    'listings': [
      {'photo': 'unsplash:1570129477492-45c003edd2be', 'title': 'Victorian terrace, Jericho', 'type': 'Sale', 'price': 685000, 'bedrooms': 3, 'area': 'Jericho', 'description': 'Light-filled family home with a walled garden, five minutes from the canal.', 'available': true},
      {'photo': 'unsplash:1497366216548-37526070297c', 'title': 'Modern flat with balcony', 'type': 'Rent', 'price': 1650, 'bedrooms': 2, 'area': 'City centre', 'description': 'Per month. Open-plan living, lift, secure parking.', 'available': true},
      {'title': 'Cottage with orchard', 'type': 'Sale', 'price': 520000, 'bedrooms': 2, 'area': 'Headington', 'description': 'Stone cottage, wood burner, apple trees and a studio.', 'available': true},
      {'title': 'Studio near the station', 'type': 'Rent', 'price': 975, 'bedrooms': 1, 'area': 'Botley', 'description': 'Per month. Bright, newly decorated, bills included.', 'available': true},
    ],
  }),
];
