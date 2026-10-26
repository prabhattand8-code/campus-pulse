# Campus Pulse — Supabase / GitHub Pages setup

This folder contains the public website, browser-side Supabase connection, database setup, and game pages. It is built for static hosting such as GitHub Pages.

## 1. Create the Supabase tables and privacy rules

1. Open your Supabase project dashboard.
2. Choose **SQL Editor** → **New query**.
3. Open supabase-setup.sql, copy all of it into the query window, then choose **Run**.
4. The query creates the tables, private college-ID and promotion-image buckets, public event-image bucket, and row-level security policies.

## 2. Put the website on GitHub Pages

Upload the contents of this folder into the root of the GitHub repository that already hosts your site. Replace the old index.html, styles.css, and game files; add live.js, supabase-config.js, and supabase-setup.sql. Commit the changes and wait for GitHub Pages to publish.

Keep supabase-config.js in the site: it contains the project's browser-safe publishable key. Never put a Supabase service_role or secret key in any website file.

## 3. Set the Supabase email redirect

After the site is published, copy its full URL, including the repository part if it has one (example: https://yourname.github.io/campus-pulse/).

In Supabase, open **Authentication** → **URL Configuration**:

- Set **Site URL** to that exact website URL.
- Add the same URL under **Redirect URLs**.

This lets users return to the website after confirming their email.

## 4. Make your account the admin

1. Open the published website and create an account using **Student**. Use your real email and college ID.
2. Confirm your email from the message Supabase sends.
   If the confirmation opens a fresh page and asks for your ID photo again, sign in and upload it once more from the account prompt.
3. In Supabase **SQL Editor**, run the following after replacing the email with the one you registered:

    update public.profiles
    set role = 'admin', verified = true
    where email = lower('you@example.com');

4. Sign in on the website using **Admin**. The Dashboard button opens the private controls.

Do not add an admin password to the website source. Supabase Auth handles passwords.

## What the site does

- Students and club members sign in with email and password; club accounts also provide the club name and intended use.
- The ID-card photo is private. Admins can open it from the review queue; verifying an account deletes the image from storage.
- The admin can publish, edit, and delete events, including posters and archive photos.
- Verified clubs can send promotion requests. The admin manually collects ₹50, then confirms receipt while approving; this copies the banner into public event media and publishes the event. The site does not process online payments.
- Tic-tac-toe, NITRR Quickfire, and Dots & Boxes are included.

The site starts with no events; add the first one from **Admin → Publish event**.

## Keeping accounts safe

Supabase Auth stores password hashes; this website never writes passwords into its own tables. Database and storage access are restricted with Supabase row-level security. College IDs and unapproved promotion banners are private; only published event media is public.

The Supabase publishable key can be included in a browser site. Its access is limited by the SQL policies. Keep all secret/service-role keys private. See the [Supabase API key guide](https://supabase.com/docs/guides/getting-started/api-keys) and [row-level security guide](https://supabase.com/docs/guides/database/postgres/row-level-security).

This package is prepared but not yet deployed to your GitHub repository. The SQL setup, email URL configuration, and GitHub Pages upload still need to be completed in your accounts.
