# Business apps and websites

A business app is where your bookings, orders and customers live. Each app is three things built from one description:

- **a public website.** Customers see your menu or services, book, and order for collection or delivery.
- **a manager page** (`/manage`), with your PIN, where you run the day.
- **tools for the AI.** On a call, the assistant books, checks and looks up in the same app, through MCP.

A booking made on the phone and one made on the website land in the same place and follow the same rules.

![A restaurant website made by LocalAILine](../screenshots/site-restaurant-home.png)

## Start from a template

**Build an app** offers eleven professional templates. Each one includes the tables, pages, sample data and rules that kind of business needs:

| Template | Highlights |
|---|---|
| Restaurant | Menu with allergens and dietary badges; table bookings by area; orders for collection, delivery (address, postcode, fee, minimum) or dine-in; gift vouchers; private dining; reviews; closed days |
| Barber, salon | Services with prices and photos; staff with bios; appointments with the barber or stylist the caller asks for; packages; vouchers |
| Dental clinic | Treatments by category; new patient and NHS/private; private medical notes; membership plans; FAQ |
| Hotel | Rooms with size, breakfast and minimum nights; a room finder by dates with the price of the stay; rooms-by-night occupancy grid |
| Garage | Services; car, registration and mileage; quotes and workshop notes; a workshop board |
| Gym | Weekly timetable with places left; class sign-ups; membership enquiries |
| Shop | Products with sale prices and stock that goes down as orders come in; collection or delivery |
| Tutoring | Courses with start dates, places and tutors; enrolments by parents |
| Events | Events with tickets left and sold out; private hire |
| Estate agent | Listings (for sale, to let, under offer, sold); viewings; valuations |

Give it your business name, phone and address, and it's ready. Your website runs at a local address shown in the app.

## Or describe your business, and the local AI builds it

You don't need a template. Choose **Build an app → Something else** and tell it, in your own words, what your business is and what customers do. For example:

> "We're a dog-grooming salon with three groomers. Customers book a wash, a trim or a full groom for their dog; we also sell shampoo and treats. We're closed on Mondays."

The local AI model then:

1. **Asks a few questions** you might not have thought of: how long a full groom takes, whether customers choose a groomer, what details you need about the dog.
2. **Proposes a plan:** the tables (services, groomers, bookings, products, orders), what customers may see or do, the pages of the website, and the look. You can change anything before it builds.
3. **Builds it:** a public website, a management website and the MCP tools for your call agents, all from the same description.

From then on your call agents can, on the phone:

- answer questions about services and prices;
- check what's free and book;
- take orders;
- find, change or cancel a caller's own booking.

All of this follows the rules the app enforces: availability, opening hours, stock, and whose booking is whose. Keep changing it in plain words ("add a page for gift vouchers", "customers can pick their groomer", "make it darker").

The same privacy rules apply to apps the AI builds as to templates. However the description is worded, customers' phone numbers, emails and notes are never public, and callers only reach their own bookings.

## The manager page

Open **Manage** from the app (or `/manage` on the website) and sign in with the app's PIN.

![Manager dashboard](../screenshots/manage-dashboard.png)

- **Dashboard:** today's bookings, open orders, takings for today and the last 7 days, 14-day charts, busiest hours, today's timeline, and what needs your attention.
- **Tables:** every booking, order and record, sortable, with status labels, totals, date filters and CSV export.
- **Board:** drag orders or jobs from one status to the next ("New → Preparing → Ready").
- **Calendar:** a day timeline, a week grid, and a month view; for hotels, rooms by night.
- **Customers:** everyone who booked or ordered, by phone number: visits, spend, last seen, next booking.
- **Design & texts:** change words, photos, colours, the delivery fee, closed days.

![Order board](../screenshots/manage-board.png)

## How the AI uses your app

Each app offers the assistant a set of tools. Every rule is enforced inside the app itself, not left to the AI:

| Tool | What it does |
|---|---|
| `check_…` | What's free at a time, or which rooms are free for some nights. It never says who booked. |
| `add_…` | Book or order. It's refused with a clear reason when a slot is taken, a day is closed, stock or places run out, or a detail is missing. |
| `find_my_…` / `change_my_…` / `cancel_my_…` | The caller's own booking only. It must be under the number they're calling from **and** the name they gave. |
| `list_…` / `get_…` | Menus, services, prices, opening hours: what customers may see anyway. |

On a call, the assistant only gets the tools of the business that was called. Extras such as gift vouchers or private events are added only once the caller mentions them; small models do better with fewer choices.

## Keeping people's details private

Apps never publish personal details. That holds even if an app's description asks for it, and for apps made by the builder:

- Tables customers add to (bookings, orders) can't be listed by customers.
- Phone numbers, emails, addresses and notes are manager-only.
- The tools answer only the assistant on this computer, with a secret key.
- The manager page locks out PIN guessing.

See [Security](../SECURITY.md).
