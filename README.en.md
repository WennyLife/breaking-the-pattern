<div align="center">

<img src="assets/icon.png" width="144" alt="Breaking the Pattern icon" />

# ⚡ Breaking the Pattern

<p align="center">
  <img src="assets/btp-0.2.3.png" width="780" alt="Breaking the Pattern 0.2.3 app window" />
  <br />
  <sub>BTP 0.2.3 — your library, game preparation and launch in one window.</sub>
</p>

### Prepare your Windows game folder to play on Mac.

[![Version](https://img.shields.io/badge/version-0.2.4-25c95a?style=for-the-badge)](https://github.com/WennyLife/breaking-the-pattern/releases/tag/v0.2.4)
![macOS](https://img.shields.io/badge/macOS-15%2B-24292f?style=for-the-badge&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Mac-Apple%20Silicon-6f42c1?style=for-the-badge)

**Bring your own supported game folder. BTP handles the preparation.**

**[📥 Download for Mac (.dmg)](https://github.com/WennyLife/breaking-the-pattern/releases/download/v0.2.4/Breaking-the-Pattern-0.2.4.dmg)** · **[📦 Download ZIP](https://github.com/WennyLife/breaking-the-pattern/releases/download/v0.2.4/Breaking-the-Pattern-0.2.4.zip)**

[Português (Brasil)](README.md) · English · [Release notes](https://github.com/WennyLife/breaking-the-pattern/releases/tag/v0.2.4)

</div>

---

## 🎮 What is BTP?

**Breaking the Pattern** prepares supported Windows games to run on Apple Silicon Macs. Select the game folder, click **BREAK**, and BTP creates a Mac app for launching the game.

Validated per-game recipes are built into the tool. BTP identifies the executable edition, obtains the required components and applies the preparation automatically. No coding or manual plugin installation is required.

**Games are not included. Each person supplies their own copy.**

## ⚡ How to use it

| 1. Select a folder | 2. Click BREAK | 3. Launch the game |
|:---|:---|:---|
| Choose the complete folder of a supported game. | BTP identifies its edition and prepares the components and fixes. | Use **OPEN GAME** or the generated app in your Applications folder. |

## 🏁 Games in this release

| Game | Confirmed result |
|:---|:---|
| **Need for Speed Underground 2** | Automatic preparation from a folder without the manual plugins; gameplay, sound and commands confirmed for the tested edition. |
| **Grand Theft Auto: San Andreas** | Automatic preparation from a folder without the manual plugins; gameplay, sound and commands confirmed for the tested edition. A 60 FPS cap is configured for compatibility. |

Support depends on the **game edition**, not just the folder name. BTP checks the executable before applying a recipe. [Accepted editions and validation →](docs/VALIDATION-0.2.3.md)

New games are added as their solutions pass gameplay validation. Splinter Cell Conviction is outside this initial release.

## 📥 Installation

1. Download **[BTP 0.2.4 DMG](https://github.com/WennyLife/breaking-the-pattern/releases/download/v0.2.4/Breaking-the-Pattern-0.2.4.dmg)** or ZIP.
2. Copy **Breaking the Pattern.app** to your local **Applications** folder.
3. Open BTP and select the complete game folder.
4. Click **BREAK**, wait for preparation, then choose **OPEN GAME**.

**Requirements:** Apple Silicon Mac, macOS 15 or later, Rosetta and internet access for the first preparation. If Rosetta is missing, BTP offers **Install and continue**: authorize the official macOS installer and preparation resumes after verification. If you cancel, you can retry from BTP. The initial runtime download is about 235 MB and expands to roughly 1.3 GB.

This version is not Apple-notarized; first launch may require macOS approval. A complete installation on another physical Mac still needs validation.

**New in 0.2.4:** guided Rosetta setup, a resizable window and **Try again** after preparation errors. First installation on a Mac without Rosetta still needs external confirmation. [Update validation →](docs/VALIDATION-0.2.4.md)

## 🔄 Updates inside BTP

Open **BTP → Updates…** or use the circular arrow in the header. You choose when to download, install and relaunch.

The production update from 0.2.2 to 0.2.3 was tested through BTP. It keeps a backup of its previous app; updating the tool preserves generated game apps, settings and saves. Apply a newer recipe to an existing game only by deliberately preparing it again.

## ✨ Included features

- **Automatic preparation:** required components and fixes for supported editions.
- **Separate game apps:** BTP can be closed after preparing a game.
- **Portuguese and English:** choose **BTP → Language / Idioma**.
- **FPS counter:** toggle with **Command + Option + 9** for games supported by its measurement adapters.
- **An updated compatibility catalog:** new recipes are added after validation.

Games continue to use a compatibility environment. Results were confirmed on this Mac and the accepted editions; performance, full campaigns and other computers need separate validation.

## 💬 Need help?

[Open a GitHub issue](https://github.com/WennyLife/breaking-the-pattern/issues/new) with the game, edition, Mac model, macOS version and symptom. Do not attach game files or saves to a public issue.

## 📚 Documentation and contribution

[0.2.3 validation](docs/VALIDATION-0.2.3.md) · [Accepted editions](scripts/game-profiles.json) · [Development](docs/DEVELOPMENT.md) · [Component licenses](THIRD_PARTY.md) · [MIT license](LICENSE)

---

<div align="center">

Developed by **[WennyLife](https://github.com/WennyLife)** · [Support the project](https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL)

</div>
