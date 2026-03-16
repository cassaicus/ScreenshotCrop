# ScreenshotCrop

!["スクショ"](https://github.com/cassaicus/ScreenshotCrop/blob/main/18.58.49.jpg)

# ScreenshotCrop

**Automatically detect and crop the content area from large sets of screenshots.**

ScreenshotCrop is a macOS tool designed to quickly process folders containing many screenshots captured from full-screen applications.

Instead of manually cropping each image, ScreenshotCrop detects the content region and applies the same crop area to every image in the folder.

This makes it easy to organize large screenshot collections efficiently.

---

## Features

• **Automatic Content Detection**
Detects the visible content region inside screenshots.

• **Batch Cropping**
Apply the same crop area to all images in a folder.

• **Overlay Preview**
Multiple screenshots can be overlaid into a single composite view to help visually identify boundaries.

• **Fast Processing**
Designed to handle large screenshot sets smoothly.

• **Manual Adjustment**
Users can easily adjust the crop area if needed.

---

## Example Workflow

1. Capture multiple screenshots from a full-screen application.
2. Place them into a folder.
3. Open the folder in ScreenshotCrop.
4. The tool automatically suggests a crop region.
5. Apply the crop to all images instantly.

---

## Use Cases

ScreenshotCrop can be useful for:

• Organizing screenshots captured during research
• Cleaning UI screenshots for documentation
• Preparing images for datasets
• Processing screenshots captured from full-screen apps

---

## Why ScreenshotCrop?

When dealing with hundreds of screenshots, manually cropping each image becomes time-consuming.

ScreenshotCrop solves this by automatically detecting the common content region across multiple screenshots and applying the crop in one step.

---

## Technical Notes

ScreenshotCrop analyzes multiple screenshots to estimate the most likely content boundaries using image processing techniques.

No external services or cloud processing are required.

All processing runs locally on your Mac.

---

## Disclaimer

ScreenshotCrop is a general screenshot processing tool.

It does **not** bypass DRM, encryption, or copy-protection mechanisms.
Users are responsible for complying with the terms of service of any applications used to capture screenshots.

---

# ScreenshotCrop

ScreenshotCropは、フルスクリーン表示の電子書籍リーダーやコミックリーダーアプリからスクリーンショットを素早くキャプチャして整理するためのmacOSツールです。

スクリーンショットのキャプチャとページ領域の検出というワークフローを自動化し、生のスクリーンショットを簡単にきれいなページ画像に変換できます。これは、手動でスクリーンショットを撮ってトリミングするのに時間がかかるフルスクリーンリーダーで特に役立ちます。

## 機能

### 自動スクリーンショットキャプチャ

ScreenshotCropは、フルスクリーン表示の電子書籍リーダーでページナビゲーションを操作するための矢印キー入力を自動的にシミュレートできます。

これにより、アプリはページを自動的にめくりながら、スクリーンショットを連続的にキャプチャできます。

### 自動背景検出

スクリーンショットをキャプチャした後、ScreenshotCropは画像を分析し、電子書籍リーダーのインターフェースで使用されている背景色を自動的に検出します。

この背景検出に基づいて、アプリは適切なトリミング領域を決定し、スクリーンショットからページコンテンツを抽出します。


### 見開きページ対応

多くのコミックやイラスト入り書籍は、見開き2ページ構成で表示されます。ScreenshotCropはこのレイアウトに対応しており、キャプチャした画像を1ページとして扱うか、見開き2ページとして扱うかを選択できます。

### 見開きページの手動選択

必要に応じて、キャプチャした画像を確認し、見開き2ページを表す画像を指定できます。

この簡単な確認手順により、1ページと見開きページが混在する書籍でも正確な結果が得られます。

## ワークフロー

1. 電子書籍リーダーまたはコミックリーダーを全画面表示で開きます。

2. ScreenshotCropを起動し、ページをめくりながら自動的にスクリーンショットをキャプチャします。

3. アプリが各スクリーンショットを分析し、背景色を検出します。

4. 検出された背景に基づいて、ページ領域が自動的に切り抜かれます。

5. 画像を確認し、見開き2ページとして扱う画像を指定します。

6. 処理を完了し、きれいなページ画像を生成します。


## 結果

ScreenshotCropは、わずか数ステップで、生のスクリーンショットを整理されたページ画像に変換します。

## プラットフォーム

* macOS

## ユースケース

* スクリーンショットから電子書籍やコミックのページをアーカイブする
* OCRや翻訳ワークフロー用の画像準備
* キャプチャした読書資料の整理

---

ScreenshotCropは、電子書籍のスクリーンショットのキャプチャと処理に伴う多くの反復作業を削減すると同時に、見開きページなどの重要なレイアウト決定をユーザーが確認できるようにします。
