# FamilyHub — Production Vercel + Supabase

## What this version does
- Private email/password authentication
- Family invite code
- Family-only RLS database access
- Real-time family chat
- Private family photo storage
- Shared tasks/work
- Family member list
- Two-device WebRTC audio/video calls using Supabase Realtime signaling

## Setup
1. Create a Supabase project.
2. Open SQL Editor and run `schema.sql`.
3. In Supabase Storage, create a bucket named `family-photos` and set it to **Private**.
4. Open Authentication → Providers → Email and enable Email/Password.
5. Copy your Supabase Project URL and anon/public key.
6. Open `index.html` and replace:
   SUPABASE_URL
   SUPABASE_ANON_KEY
7. Save the file as `index.html`.
8. Deploy the folder to Vercel.

## Create the first family
The first family administrator needs an account. Because the HTML UI is intentionally invite-only for joining existing families, use Supabase SQL Editor once to create the first family and link the first user, or temporarily add a small admin bootstrap call.

After the first admin account exists, the easiest bootstrap is:
- Sign up the admin in the app.
- In Supabase SQL Editor, run:

select public.create_family('My Family','A-PRIVATE-CODE-2026');

The function uses the currently authenticated SQL session only when called through an authenticated client. If your SQL editor session is not the same user, create the family through a tiny authenticated console call:
await db.rpc('create_family',{p_name:'My Family',p_code:'A-PRIVATE-CODE-2026'});

Then the admin can show the invite code from Members.

## Vercel
No build command is needed. Upload the folder containing `index.html` and `schema.sql`, or connect the folder to a GitHub repository and import it into Vercel.

## Important security notes
- Never put a Supabase `service_role` key in HTML.
- Use only the public/anon key in `index.html`.
- Keep the `family-photos` bucket private.
- RLS policies are the security boundary; do not disable them.
- WebRTC uses STUN servers. Some restrictive networks may require a TURN server for calls to work reliably.
