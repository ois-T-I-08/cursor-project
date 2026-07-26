# Third-party notices

運営者（ois-T-I-08）の自作コード・文書はリポジトリルートの [MIT License](../LICENSE) です。  
以下の第三者コード・データ・サービスは、リポジトリルートの MIT License ではなく、それぞれのライセンス・利用条件に従います。書面許可が未確認のものは「許可済み」とは記載しません。

## Currently used data / services

### gcsim

- Project: <https://github.com/genshinsim/gcsim>
- Role: Optional team-simulation engine used by the recommendation backend
- Fixed version used by the adapter: `v2.43.4`
- Default: `GCSIM_ENABLED=false`; the application does not bundle the gcsim binary in this repository
- Copyright: Copyright (c) 2021 genshinsim
- License: MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

gcsim is an independent open-source simulator. Simulation values are theoretical and are not guarantees of in-game performance.

### Project Amber (gi.yatta.moe)

- Role: Game master data source for character / weapon / material sync (mobile + backend sync paths)
- License / redistribution: **Not confirmed for redistribution as our own data.** Treated as third-party reference data.
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
