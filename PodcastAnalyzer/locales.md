# Apple Podcasts storefronts

Generated, not hand-written. Every ISO 3166-1 alpha-2 code was probed against

```
https://rss.marketingtools.apple.com/api/v2/{code}/podcasts/top/1/podcasts.json
```

A live storefront answers **HTTP 200**; a nonexistent one answers **HTTP 500**.
That is also how the in-app "Test" button for a custom storefront works.

- Verified: **2026-08-22**
- Live storefronts: **174** of 249 codes probed
- Source of truth for `Storefronts.swift` — regenerate both together.

The *Feed title* column is the localized name Apple returns for that storefront,
which doubles as a check that the storefront really is localized and not just
a US mirror.

| Code | Flag | Name | Feed title |
|------|------|------|------------|
| `af` | 🇦🇫 | Afghanistan | Top Shows |
| `al` | 🇦🇱 | Albania | Top Shows |
| `dz` | 🇩🇿 | Algeria | Top Shows |
| `ao` | 🇦🇴 | Angola | Top Shows |
| `ai` | 🇦🇮 | Anguilla | Top Shows |
| `ag` | 🇦🇬 | Antigua & Barbuda | Top Shows |
| `ar` | 🇦🇷 | Argentina | Top programas |
| `am` | 🇦🇲 | Armenia | Top Shows |
| `au` | 🇦🇺 | Australia | Top Shows |
| `at` | 🇦🇹 | Austria | Top-Podcasts |
| `az` | 🇦🇿 | Azerbaijan | Top Shows |
| `bs` | 🇧🇸 | Bahamas | Top Shows |
| `bh` | 🇧🇭 | Bahrain | Top Shows |
| `bb` | 🇧🇧 | Barbados | Top Shows |
| `by` | 🇧🇾 | Belarus | Top Shows |
| `be` | 🇧🇪 | Belgium | Top Shows |
| `bz` | 🇧🇿 | Belize | Top Shows |
| `bj` | 🇧🇯 | Benin | Top Shows |
| `bm` | 🇧🇲 | Bermuda | Top Shows |
| `bt` | 🇧🇹 | Bhutan | Top Shows |
| `bo` | 🇧🇴 | Bolivia | Top programas |
| `ba` | 🇧🇦 | Bosnia & Herzegovina | Top Shows |
| `bw` | 🇧🇼 | Botswana | Top Shows |
| `br` | 🇧🇷 | Brazil | Principais podcasts |
| `vg` | 🇻🇬 | British Virgin Islands | Top Shows |
| `bn` | 🇧🇳 | Brunei | Top Shows |
| `bg` | 🇧🇬 | Bulgaria | Top Shows |
| `bf` | 🇧🇫 | Burkina Faso | Top Shows |
| `kh` | 🇰🇭 | Cambodia | Top Shows |
| `cm` | 🇨🇲 | Cameroon | Classement des émissions |
| `ca` | 🇨🇦 | Canada | Top Shows |
| `cv` | 🇨🇻 | Cape Verde | Top Shows |
| `ky` | 🇰🇾 | Cayman Islands | Top Shows |
| `td` | 🇹🇩 | Chad | Top Shows |
| `cl` | 🇨🇱 | Chile | Top programas |
| `cn` | 🇨🇳 | China mainland | 热门节目 |
| `co` | 🇨🇴 | Colombia | Top programas |
| `cg` | 🇨🇬 | Congo - Brazzaville | Top Shows |
| `cd` | 🇨🇩 | Congo - Kinshasa | Top Shows |
| `cr` | 🇨🇷 | Costa Rica | Top programas |
| `hr` | 🇭🇷 | Croatia | Top Shows |
| `cy` | 🇨🇾 | Cyprus | Top Shows |
| `cz` | 🇨🇿 | Czechia | Top Shows |
| `ci` | 🇨🇮 | Côte d’Ivoire | Classement des émissions |
| `dk` | 🇩🇰 | Denmark | Top Shows |
| `dm` | 🇩🇲 | Dominica | Top Shows |
| `do` | 🇩🇴 | Dominican Republic | Top programas |
| `ec` | 🇪🇨 | Ecuador | Top programas |
| `eg` | 🇪🇬 | Egypt | Top Shows |
| `sv` | 🇸🇻 | El Salvador | Top programas |
| `ee` | 🇪🇪 | Estonia | Top Shows |
| `sz` | 🇸🇿 | Eswatini | Top Shows |
| `fj` | 🇫🇯 | Fiji | Top Shows |
| `fi` | 🇫🇮 | Finland | Top Shows |
| `fr` | 🇫🇷 | France | Classement des émissions |
| `ga` | 🇬🇦 | Gabon | Classement des émissions |
| `gm` | 🇬🇲 | Gambia | Top Shows |
| `ge` | 🇬🇪 | Georgia | Top Shows |
| `de` | 🇩🇪 | Germany | Top-Podcasts |
| `gh` | 🇬🇭 | Ghana | Top Shows |
| `gr` | 🇬🇷 | Greece | Top Shows |
| `gd` | 🇬🇩 | Grenada | Top Shows |
| `gt` | 🇬🇹 | Guatemala | Top programas |
| `gw` | 🇬🇼 | Guinea-Bissau | Top Shows |
| `gy` | 🇬🇾 | Guyana | Top Shows |
| `hn` | 🇭🇳 | Honduras | Top programas |
| `hk` | 🇭🇰 | Hong Kong | 熱門節目 |
| `hu` | 🇭🇺 | Hungary | Top Shows |
| `is` | 🇮🇸 | Iceland | Top Shows |
| `in` | 🇮🇳 | India | Top Shows |
| `id` | 🇮🇩 | Indonesia | Top Shows |
| `iq` | 🇮🇶 | Iraq | Top Shows |
| `ie` | 🇮🇪 | Ireland | Top Shows |
| `il` | 🇮🇱 | Israel | Top Shows |
| `it` | 🇮🇹 | Italy | Top podcast |
| `jm` | 🇯🇲 | Jamaica | Top Shows |
| `jp` | 🇯🇵 | Japan | トップ番組 |
| `jo` | 🇯🇴 | Jordan | Top Shows |
| `kz` | 🇰🇿 | Kazakhstan | Top Shows |
| `ke` | 🇰🇪 | Kenya | Top Shows |
| `kw` | 🇰🇼 | Kuwait | Top Shows |
| `kg` | 🇰🇬 | Kyrgyzstan | Top Shows |
| `la` | 🇱🇦 | Laos | Top Shows |
| `lv` | 🇱🇻 | Latvia | Top Shows |
| `lb` | 🇱🇧 | Lebanon | Top Shows |
| `lr` | 🇱🇷 | Liberia | Top Shows |
| `ly` | 🇱🇾 | Libya | Top Shows |
| `lt` | 🇱🇹 | Lithuania | Top Shows |
| `lu` | 🇱🇺 | Luxembourg | Top Shows |
| `mo` | 🇲🇴 | Macao | 熱門節目 |
| `mg` | 🇲🇬 | Madagascar | Top Shows |
| `mw` | 🇲🇼 | Malawi | Top Shows |
| `my` | 🇲🇾 | Malaysia | Top Shows |
| `mv` | 🇲🇻 | Maldives | Top Shows |
| `ml` | 🇲🇱 | Mali | Top Shows |
| `mt` | 🇲🇹 | Malta | Top Shows |
| `mr` | 🇲🇷 | Mauritania | Top Shows |
| `mu` | 🇲🇺 | Mauritius | Top Shows |
| `mx` | 🇲🇽 | Mexico | Top programas |
| `fm` | 🇫🇲 | Micronesia | Top Shows |
| `md` | 🇲🇩 | Moldova | Top Shows |
| `mn` | 🇲🇳 | Mongolia | Top Shows |
| `me` | 🇲🇪 | Montenegro | Top Shows |
| `ms` | 🇲🇸 | Montserrat | Top Shows |
| `ma` | 🇲🇦 | Morocco | Top Shows |
| `mz` | 🇲🇿 | Mozambique | Top Shows |
| `mm` | 🇲🇲 | Myanmar (Burma) | Top Shows |
| `na` | 🇳🇦 | Namibia | Top Shows |
| `nr` | 🇳🇷 | Nauru | Top Shows |
| `np` | 🇳🇵 | Nepal | Top Shows |
| `nl` | 🇳🇱 | Netherlands | Topprogramma's |
| `nz` | 🇳🇿 | New Zealand | Top Shows |
| `ni` | 🇳🇮 | Nicaragua | Top programas |
| `ne` | 🇳🇪 | Niger | Top Shows |
| `ng` | 🇳🇬 | Nigeria | Top Shows |
| `mk` | 🇲🇰 | North Macedonia | Top Shows |
| `no` | 🇳🇴 | Norway | Top Shows |
| `om` | 🇴🇲 | Oman | Top Shows |
| `pk` | 🇵🇰 | Pakistan | Top Shows |
| `pw` | 🇵🇼 | Palau | Top Shows |
| `pa` | 🇵🇦 | Panama | Top programas |
| `pg` | 🇵🇬 | Papua New Guinea | Top Shows |
| `py` | 🇵🇾 | Paraguay | Top programas |
| `pe` | 🇵🇪 | Peru | Top programas |
| `ph` | 🇵🇭 | Philippines | Top Shows |
| `pl` | 🇵🇱 | Poland | Top Shows |
| `pt` | 🇵🇹 | Portugal | Top de programas |
| `qa` | 🇶🇦 | Qatar | Top Shows |
| `ro` | 🇷🇴 | Romania | Top Shows |
| `ru` | 🇷🇺 | Russia | Топ-подкасты |
| `rw` | 🇷🇼 | Rwanda | Top Shows |
| `sa` | 🇸🇦 | Saudi Arabia | Top Shows |
| `sn` | 🇸🇳 | Senegal | Top Shows |
| `rs` | 🇷🇸 | Serbia | Top Shows |
| `sc` | 🇸🇨 | Seychelles | Top Shows |
| `sl` | 🇸🇱 | Sierra Leone | Top Shows |
| `sg` | 🇸🇬 | Singapore | Top Shows |
| `sk` | 🇸🇰 | Slovakia | Top Shows |
| `si` | 🇸🇮 | Slovenia | Top Shows |
| `sb` | 🇸🇧 | Solomon Islands | Top Shows |
| `za` | 🇿🇦 | South Africa | Top Shows |
| `kr` | 🇰🇷 | South Korea | 인기 프로그램 |
| `es` | 🇪🇸 | Spain | Top programas |
| `lk` | 🇱🇰 | Sri Lanka | Top Shows |
| `kn` | 🇰🇳 | St. Kitts & Nevis | Top Shows |
| `lc` | 🇱🇨 | St. Lucia | Top Shows |
| `vc` | 🇻🇨 | St. Vincent & Grenadines | Top Shows |
| `sr` | 🇸🇷 | Suriname | Top Shows |
| `se` | 🇸🇪 | Sweden | Poddtoppen |
| `ch` | 🇨🇭 | Switzerland | Top-Podcasts |
| `st` | 🇸🇹 | São Tomé & Príncipe | Top Shows |
| `tw` | 🇹🇼 | Taiwan | 熱門節目 |
| `tj` | 🇹🇯 | Tajikistan | Top Shows |
| `tz` | 🇹🇿 | Tanzania | Top Shows |
| `th` | 🇹🇭 | Thailand | Top Shows |
| `to` | 🇹🇴 | Tonga | Top Shows |
| `tt` | 🇹🇹 | Trinidad & Tobago | Top Shows |
| `tn` | 🇹🇳 | Tunisia | Top Shows |
| `tm` | 🇹🇲 | Turkmenistan | Top Shows |
| `tc` | 🇹🇨 | Turks & Caicos Islands | Top Shows |
| `tr` | 🇹🇷 | Türkiye | Top Shows |
| `ug` | 🇺🇬 | Uganda | Top Shows |
| `ua` | 🇺🇦 | Ukraine | Top Shows |
| `ae` | 🇦🇪 | United Arab Emirates | Top Shows |
| `gb` | 🇬🇧 | United Kingdom | Top Shows |
| `us` | 🇺🇸 | United States | Top Shows |
| `uy` | 🇺🇾 | Uruguay | Top Shows |
| `uz` | 🇺🇿 | Uzbekistan | Top Shows |
| `vu` | 🇻🇺 | Vanuatu | Top Shows |
| `ve` | 🇻🇪 | Venezuela | Top programas |
| `vn` | 🇻🇳 | Vietnam | Top Shows |
| `ye` | 🇾🇪 | Yemen | Top Shows |
| `zm` | 🇿🇲 | Zambia | Top Shows |
| `zw` | 🇿🇼 | Zimbabwe | Top Shows |

## Codes probed and not available

These returned 500 and are not Apple Podcasts storefronts:

`ad`, `aq`, `as`, `aw`, `ax`, `bd`, `bi`, `bl`, `bq`, `bv`, `cc`, `cf`, `ck`, `cu`, `cw`, `cx`, `dj`, `eh`, `er`, `et`, `fk`, `fo`, `gf`, `gg`, `gi`, `gl`, `gn`, `gp`, `gq`, `gs`, `gu`, `hm`, `ht`, `im`, `io`, `ir`, `je`, `ki`, `km`, `kp`, `li`, `ls`, `mc`, `mf`, `mh`, `mp`, `mq`, `nc`, `nf`, `nu`, `pf`, `pm`, `pn`, `pr`, `ps`, `re`, `sd`, `sh`, `sj`, `sm`, `so`, `ss`, `sx`, `sy`, `tf`, `tg`, `tk`, `tl`, `tv`, `um`, `va`, `vi`, `wf`, `ws`, `yt`
