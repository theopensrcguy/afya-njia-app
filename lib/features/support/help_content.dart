import 'package:flutter/material.dart';

/// What's written in Msaada (v0.48.2): common questions, and Mwongozo, the
/// step-by-step "how to use the app". Kiswahili is the key; English lives in
/// i18n_en.dart like every other text. Kept in the app so it opens with no
/// network, which is exactly when people need help.
class HelpQuestion {
  const HelpQuestion(this.topic, this.q, this.a);
  final String topic;
  final String q;
  final String a;
}

class HelpGuide {
  const HelpGuide(this.icon, this.title, this.why, this.steps);
  final IconData icon;
  final String title;
  final String why;
  final List<String> steps;
}

const helpTopics = ['Kuanza', 'Mauzo', 'Hisa', 'Mizigo', 'Malipo', 'Akaunti'];

const helpQuestions = <HelpQuestion>[
  HelpQuestion('Kuanza', 'Nianzie wapi duka likiwa jipya?',
      'Ingiza hisa yako ya mwanzo: Hisa → Pokea mzigo (au Ingiza kwa wingi kwenye kompyuta). Kisha ongeza wafanyakazi kwenye Zaidi → Wafanyakazi, na uanze kuuza kwenye Uza.'),
  HelpQuestion('Kuanza', 'Mfanyakazi mpya ataingiaje?',
      'Mwongeze kwenye Zaidi → Wafanyakazi na namba yake ya simu na PIN ya muda. Akiingia mara ya kwanza atachagua PIN yake mwenyewe. Simu yake mpya itasubiri uiruhusu kwenye Vifaa.'),
  HelpQuestion('Kuanza', 'Simu mpya inasema "inasubiri idhini"',
      'Ni kwa usalama: kila simu mpya lazima mmiliki airuhusu. Kwenye simu ya mmiliki fungua Vifaa, hakikisha namba 6 zinalingana na zilizo kwenye simu mpya, kisha gusa Ruhusu.'),
  HelpQuestion('Mauzo', 'Nimekosea mauzo, nifanyeje?',
      'Fungua Mauzo, gusa mauzo hayo, kisha Futa na uandike sababu. Hisa inarudi rafuni. Muuzaji anaweza kufuta mauzo yake ndani ya dakika chache; baada ya hapo ni mmiliki au mwenye ruhusa.'),
  HelpQuestion('Mauzo', 'Mteja analipa sehemu kwa M-Pesa na sehemu taslimu',
      'Kwenye Kamilisha gusa Gawanya malipo. Andika kiasi cha M-Pesa; kinachobaki kinajazwa chenyewe kama taslimu.'),
  HelpQuestion('Mauzo', 'Mteja ameulizia dawa ambayo hatuna',
      'Ukitafuta na isionekane, au imeisha, gusa "Mteja ameulizia". Itaonekana kwenye Agiza → Wanaouliza, na ikifika utaambiwa uwajulishe.'),
  HelpQuestion('Hisa', 'Idadi kwenye app hailingani na rafu',
      'Fanya Hesabu ya hisa (Hisa → ikoni ya ubao). Hesabu unachokiona; app inakuonyesha tofauti, na mwenye ruhusa anaidhinisha marekebisho.'),
  HelpQuestion('Hisa', 'Dawa imeisha muda wake',
      'Fungua bidhaa kwenye Hisa, gusa batch iliyoisha muda, kisha Andika kama hasara. Inaondoka kwenye hisa na kuonekana kwenye hasara za ripoti.'),
  HelpQuestion('Hisa', 'Nawekaje picha ya dawa?',
      'Fungua bidhaa kwenye Hisa na gusa mraba wa picha, au piga picha unapohesabu hisa au kupokea bidhaa mpya. Picha inaonekana kila mahali.'),
  HelpQuestion('Mizigo', 'Mfanyakazi amepokea mzigo, mbona hisa haijaongezeka?',
      'Mzigo wa mfanyakazi unasubiri uthibitisho. Mwenye ruhusa afungue Mizigo, akague, kisha Thibitisha. Hakuna anayethibitisha mzigo wake mwenyewe.'),
  HelpQuestion('Mizigo', 'Naagizaje kwa msambazaji?',
      'Fungua Agiza. Weka unachohitaji kwenye kikapu (au Anza na pendekezo), kisha gusa kikapu → Tuma. Kila msambazaji anapata ujumbe wake wa WhatsApp.'),
  HelpQuestion('Malipo', 'Usajili wangu unaisha, nalipaje?',
      'Mmiliki ataona taarifa juu ya ukurasa wa mwanzo. Gusa Lipia sasa, chagua kipindi, mtandao na namba, kisha thibitisha kwa PIN ya simu yako.'),
  HelpQuestion('Malipo', 'Duka limekuwa "la kusoma tu"',
      'Usajili umeisha. Bado unaona kila kitu lakini huwezi kuhifadhi. Lipia kwenye Maduka yangu → Lipia, na kila kitu kinarudi papo hapo.'),
  HelpQuestion('Akaunti', 'Nimesahau PIN yangu',
      'Kwenye ukurasa wa kuingia gusa "Umesahau PIN?". Utapata namba 6 kwa SMS, kisha uchague PIN mpya. Saola hawatakuuliza PIN yako kamwe.'),
  HelpQuestion('Akaunti', 'Nabadilishaje lugha?',
      'Gusa picha yako juu ya ukurasa wa mwanzo → Lugha, chagua Kiswahili au English. Inafuata akaunti yako kwenye simu na kompyuta.'),
  HelpQuestion('Akaunti', 'Saola watanijibu lini?',
      'Ukiomba msaada chagua linahusu nini na ni la haraka kiasi gani. "Dharura" (hamwezi kuingia au kuuza) inajibiwa kwanza, kisha "Muhimu", kisha maswali ya kawaida. Usichague dharura kwa swali: inawachelewesha walio na dharura kweli.'),
  HelpQuestion('Akaunti', 'Nina maduka mawili',
      'Ukiwa na namba moja, maduka yote yanaonekana kwenye Maduka yangu. Gusa Fungua kubadili duka bila kutoka.'),
];

const helpGuides = <HelpGuide>[
  HelpGuide(Icons.point_of_sale_rounded, 'Kuuza', 'Mauzo ya kila siku, kwa haraka', [
    'Gusa Uza kwenye ukurasa wa mwanzo.',
    'Tafuta dawa kwa jina, au gusa kigae cha Haraka, au skani barcode.',
    'Gusa kipimo (kidonge, kadi, boksi) kuongeza kwenye kikapu. Gusa namba kuandika idadi.',
    'Gusa Lipa, chagua njia ya malipo (Taslimu, Simu, Bima, Deni) na weka punguzo kama lipo.',
    'Gusa Kamilisha. Unaweza kutuma risiti kwa WhatsApp au kumkumbusha mteja kurudia dawa.',
  ]),
  HelpGuide(Icons.inventory_2_outlined, 'Kupokea mzigo', 'Hisa inayoingia kutoka kwa msambazaji', [
    'Fungua Hisa → Pokea mzigo.',
    'Chagua msambazaji, andika namba ya ankara na jumla yake, piga picha ya ankara.',
    'Ongeza kila bidhaa: kifungashio, idadi, batch, EXP na bei ya kununua.',
    'Angalia jumla inalingana na ankara, kisha Hifadhi.',
    'Kama wewe si mmiliki, mzigo unasubiri uthibitisho kwenye Mizigo.',
  ]),
  HelpGuide(Icons.shopping_basket_outlined, 'Kuagiza mzigo', 'Usiishiwe na dawa zinazouzika', [
    'Fungua Agiza. Zinahitajika ni zilizoisha, zilizo chini, zitakazoisha na walizouliza wateja.',
    'Gusa Anza na pendekezo kuweka zote kikapuni, au + Weka kwa unazotaka moja moja.',
    'Shikilia bidhaa kuchagua kadhaa; × inaiweka pembeni kwa siku 7.',
    'Weka bajeti ukipenda: zinazohitajika zaidi zinabaki kwanza.',
    'Gusa kikapu → Tuma (WhatsApp kwa kila msambazaji), Orodha ya kununua (kwenda Kariakoo), au Hifadhi kwa baadaye.',
  ]),
  HelpGuide(Icons.fact_check_outlined, 'Hesabu ya hisa', 'Rafu na app zilingane', [
    'Fungua Hisa → ikoni ya ubao, kisha Anza hesabu na uchague aina (rafu moja, zinazoleta pesa, kamili…).',
    'Gusa bidhaa, hesabu kilicho rafuni, andika idadi. Namba ya mfumo inaonekana baada ya kuhifadhi.',
    'Ukimaliza gusa Maliza na tuma.',
    'Mwenye ruhusa anakagua tofauti na kuidhinisha. Mauzo yanaendelea wakati wa kuhesabu.',
  ]),
  HelpGuide(Icons.receipt_long_outlined, 'Madeni', 'Kuuza kwa deni na kupokea malipo', [
    'Kwenye Kamilisha chagua Deni, kisha mteja (au mwongeze).',
    'Kama huna ruhusa ya kuidhinisha, ombi linaenda kwa mmiliki; ukikubaliwa mpe mteja dawa.',
    'Mteja akilipa: Zaidi → Madeni → mteja → Pokea malipo.',
    'Kumbusha wanaodaiwa kwa SMS, WhatsApp au simu kutoka ukurasa wa mteja.',
  ]),
  HelpGuide(Icons.payments_outlined, 'Matumizi', 'Pesa inayotoka nje ya mzigo', [
    'Fungua Zaidi → Matumizi → Ongeza matumizi.',
    'Chagua aina (kodi, umeme, mishahara…), kiasi, na njia ya malipo.',
    'Taslimu inapunguzwa kwenye droo ya zamu. Faida baada ya matumizi inaonekana kwenye Fedha.',
  ]),
  HelpGuide(Icons.badge_outlined, 'Wafanyakazi na ruhusa', 'Kila mtu anaona na kufanya anachopaswa', [
    'Fungua Zaidi → Wafanyakazi → Ongeza mfanyakazi (jina, namba, PIN ya muda).',
    'Washa ruhusa moja moja, au tumia Msaidizi / Msimamizi. Unaweza kuweka "mpaka lini".',
    'Mfanyakazi akiacha kazi: ⋮ → Simamisha. Anatolewa kila mahali papo hapo.',
    '🖨 inachapisha orodha ya wafanyakazi bila taarifa binafsi.',
  ]),
  HelpGuide(Icons.phonelink_lock_outlined, 'Simu mpya', 'Kwa nini simu inasubiri idhini', [
    'Mtu akiingia kwenye simu mpya, inaonyesha namba 6 na kusubiri.',
    'Mmiliki anafungua Vifaa kwenye simu yake, analinganisha namba, anagusa Ruhusu.',
    'Simu ya kaunta inaweza kuwa ya pamoja: kila mtu anaingia kwa PIN yake.',
    'Simu ikipotea: Vifaa → Ondoa. Inatolewa papo hapo.',
  ]),
  HelpGuide(Icons.swap_horiz_rounded, 'Uhamisho wa hisa', 'Kuazimana hisa na duka jingine', [
    'Fungua Zaidi → Uhamisho. Tuma namba ya duka lako kwa duka jingine, au gusa Unganisha na uandike yao.',
    'Mkiunganishwa, gusa Uhamisho mpya: chagua duka, bidhaa na idadi, kisha Tuma.',
    'Duka lingine linagusa Pokea mzigo (inaingia kwao) au Kataa (inarudi kwako).',
  ]),
  HelpGuide(Icons.people_alt_outlined, 'Wateja na vikumbusho', 'Wateja warudi kwa wakati', [
    'Fungua Zaidi → Wateja → Sajili mteja, kwa ridhaa yake.',
    'Baada ya mauzo, gusa Mkumbushe kurudia dawa na uweke siku.',
    'Kila siku, Wateja inaonyesha wa kukumbushwa leo. Gusa Tuma (WhatsApp). Ujumbe hautaji dawa.',
  ]),
  HelpGuide(Icons.ios_share_rounded, 'Ripoti na kushiriki', 'Namba za duka kwa mshirika au mhasibu', [
    'Fedha na Ripoti zinaonyesha mauzo, faida na mambo ya kufanya sasa.',
    'Kwenye Mauzo, Hisa au Mizigo gusa kitufe cha kushiriki: chagua kipindi, kisha PDF au Excel.',
    'Fungua kuchapisha, tuma kwa WhatsApp, au nakili kiungo (kinafanya kazi siku 3).',
  ]),
];
