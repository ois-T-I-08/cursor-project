# Third-party notices

運営者（ois-T-I-08）の自作コード・文書はリポジトリルートの [MIT License](../LICENSE) です。  
以下は **MIT の対象外**です。利用条件・再配布可否は各提供者の規約に従います。書面許可が未確認のものは「許可済み」とは記載しません。

## Currently used data / services

### Project Amber (gi.yatta.moe)

- Role: Game master data source for character / weapon / material sync (mobile + backend sync paths)
- License / redistribation: **Not confirmed for redistribution as our own data.** Treated as third-party reference data.
- Status: Usage permission and redistribution terms are **pending owner confirmation** with the upstream project terms.

### AZA.GG

- Role: Spiral Abyss character/team usage statistics shown in the app via our backend (`/api/abyss/statistics`)
- License / redistribation: **Not confirmed as an unrestricted license.** Displayed with attribution in the UI.
- Status: Commercial / redistribution terms are **pending confirmation.** Do not treat as MIT-covered content.

### HoYoLAB / HoYoverse

- Role: Optional account linking (cookies / game roles / daily notes) initiated by the user in the mobile app
- Data: Auth cookies and related identifiers stay on-device in Secure Storage; they are sent to HoYoLAB / HoYoverse APIs, not retained as operator-owned content under MIT
- Status: Subject to HoYoverse / HoYoLAB terms. **Not MIT-licensed.** Operator servers must not receive or store HoYoLAB cookies.

### YShelper

- Role: Optional battle-statistics collection pipeline (GitHub Actions → Neon → public APIs) behind kill switches
- Status: Written permission for use, storage, processing, and redistribution is **not obtained.** Production collection and schedules remain disabled until documented approval exists.
- Do not assume YShelper data is MIT-licensed or redistributable.

### Genshin Impact / HoYoverse IP

Names, characters, weapons, images, icons, trademarks, logos, in-game values, and game data belong to their rights holders. This project is an unofficial fan tool and does not grant rights to those assets.

## Removed / not in use

- **gcsim**: Previously evaluated for team simulation; **removed from the product.** Do not treat as a current dependency.
