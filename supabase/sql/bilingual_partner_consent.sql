alter table public.carmitra_partner_applications
 add column transportation boolean not null default false,
 add column agreement_accepted_at timestamptz,
 add column agreement_version text,
 add column agreement_snapshot text;
alter table public.carmitra_partners add column agreement_snapshot text;
update public.carmitra_site_settings set agreement_version='partner-v2-2026-10-13',agreement_text='English Version

This agreement establishes that the Partner is an independent contractor and not an employee of CarMitra. The Partner is responsible for their behavior, vehicle, equipment, and service outcome. CarMitra acts only as an intermediary platform providing booking leads. The Partner agrees to follow CarMitra''s Code of Conduct, Dress Code (Black/Yellow/Blue T-shirt, shoes), Photo ID badge, Before/After Photo uploads, and Customer Signature. Partner accepts a commission model where 90% of service fee is transferred to Partner and 10% is retained by CarMitra as platform commission. Any customer damage claims will be settled directly by partner; platform is not liable. Termination may occur if performance or conduct fails CarMitra standards.

Hindi Version

यह समझौता स्पष्ट करता है कि पार्टनर स्वतंत्र सेवा प्रदाता है, CarMitra का कर्मचारी नहीं। पार्टनर अपनी सेवा, व्यवहार, वाहन, उपकरण और परिणाम के लिए स्वयं जिम्मेदार होगा। CarMitra केवल बुकिंग लीड प्रदान करता है और मध्यस्थ की भूमिका निभाता है। पार्टनर को CarMitra की ड्रेस कोड (ब्लैक/येलो/ब्लू टी-शर्ट, जूते), फोटो आईडी बैज, सेवा से पहले/बाद की फोटो अपलोड, और ग्राहक की डिजिटल सिग्नेचर प्रक्रिया को फॉलो करना अनिवार्य है। पार्टनर राज़ी है कि हर बुकिंग पर 90% भुगतान पार्टनर को और 10% कमीशन CarMitra को मिलेगा। किसी भी नुकसान या विवाद की जिम्मेदारी पार्टनर की होगी। CarMitra आवश्यक होने पर नियम उल्लंघन पर खाता बंद कर सकता है।

Acceptance

I agree to the Partner Agreement (मैं सहमत हूँ) - I confirm that I have read and understood the terms and conditions, and I accept to work as an independent contractor with a 90/10 commission split.' where id=true;
do $patch$
declare definition text := pg_get_functiondef('carmitra_internal.portal(text,jsonb)'::regprocedure);
begin
 if strpos(definition,'equipment,documents) values')=0 or strpos(definition,'documents=excluded.documents,status=')=0 then raise exception 'Unexpected portal definition';end if;
 definition:=replace(definition,'if action=''apply_partner'' then','if action=''apply_partner'' then
  if coalesce((p->>''agreement_accept'')::boolean,false) is not true then raise exception ''Accept the Partner Agreement before submitting'';end if;
  if (p->>''agreement_version'') is distinct from s.agreement_version then raise exception ''The agreement has changed. Refresh and review the current terms'';end if;');
 definition:=replace(definition,'equipment,documents) values','equipment,documents,transportation,agreement_accepted_at,agreement_version,agreement_snapshot) values');
 definition:=replace(definition,'(p->>''equipment'')::boolean,p->''documents'') on conflict(user_id)','(p->>''equipment'')::boolean,p->''documents'',coalesce((p->>''transportation'')::boolean,false),now(),s.agreement_version,s.agreement_text) on conflict(user_id)');
 definition:=replace(definition,'documents=excluded.documents,status=','documents=excluded.documents,transportation=excluded.transportation,agreement_accepted_at=excluded.agreement_accepted_at,agreement_version=excluded.agreement_version,agreement_snapshot=excluded.agreement_snapshot,status=');
 definition:=replace(definition,'if coalesce((p->>''accept'')::boolean,false) is not true then raise exception ''Accept the partner agreement'';end if;','if coalesce((p->>''accept'')::boolean,false) is not true then raise exception ''Accept the partner agreement'';end if;
  if (p->>''agreement_version'') is distinct from s.agreement_version then raise exception ''Refresh and review the current Partner Agreement'';end if;');
 definition:=replace(definition,'agreement_signed_at=now(),agreement_version=s.agreement_version','agreement_signed_at=now(),agreement_version=s.agreement_version,agreement_snapshot=s.agreement_text');
 execute definition;
end $patch$;
