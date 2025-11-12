//
//  CoverFlowPagerView.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import SwiftUI
import UIKit

// MARK: - Parameters & Helpers

struct CoverFlowParameters: Equatable {
  var cardWidthRatio: Double = 0.62
  var maxCardWidth: Double = 280
  var spacingMultiplier: Double = 1.0
  var rotationFactor: Double = 1.35
  var translationFactor: Double = 0.45
  var perspective: Double = 0.002
  var minimumScale: Double = 0.84
  var minimumAlpha: Double = 0.45
  var usesAdaptiveSnapping: Bool = true
  var manualDeceleration: Double = 1

  mutating func reset() { self = .default }
}

extension CoverFlowParameters {
  static let `default` = CoverFlowParameters()

  func cardSize(for totalWidth: CGFloat) -> CGSize {
    let width = min(CGFloat(maxCardWidth), max(140, totalWidth * cardWidthRatio))
    return CGSize(width: width, height: width * 1.5)
  }

  var decelerationValue: UInt {
    usesAdaptiveSnapping ? FSPagerView.automaticDistance : max(1, UInt(manualDeceleration.rounded()))
  }

  var cgMinimumScale: CGFloat { CGFloat(minimumScale) }
  var cgMinimumAlpha: CGFloat { CGFloat(minimumAlpha) }
  var cgPerspective: CGFloat { CGFloat(perspective) }
  var rotationMultiplier: CGFloat { CGFloat(rotationFactor) }
  var translationMultiplier: CGFloat { CGFloat(translationFactor) }
  var spacingFactor: CGFloat { CGFloat(spacingMultiplier) }
}

// MARK: - Pager View

struct CoverFlowPagerView: UIViewRepresentable {
  let suggestions: [Suggestion]
  @Binding var currentIndex: Int
  var cardSize: CGSize
  var parameters: CoverFlowParameters

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> FSPagerView {
    let pager = FSPagerView()
    pager.register(FSPagerViewCell.self, forCellWithReuseIdentifier: Coordinator.reuseIdentifier)
    pager.dataSource = context.coordinator
    pager.delegate = context.coordinator
    pager.backgroundColor = .clear
    pager.bounces = true
    pager.isInfinite = true
    pager.removesInfiniteLoopForSingleItem = true
    pager.itemSize = cardSize
    pager.decelerationDistance = parameters.decelerationValue
    pager.interitemSpacing = 0
    pager.transformer = AdjustableCoverFlowTransformer(parameters: parameters)
    return pager
  }

  func updateUIView(_ pager: FSPagerView, context: Context) {
    context.coordinator.parent = self
    apply(parameters, to: pager)

    if context.coordinator.cachedCount != suggestions.count {
      context.coordinator.cachedCount = suggestions.count
      pager.reloadData()
    } else {
      pager.collectionViewLayout.invalidateLayout()
    }

    if suggestions.indices.contains(currentIndex),
       pager.currentIndex != currentIndex {
      pager.scrollToItem(at: currentIndex, animated: true)
    }
  }

  private func apply(_ parameters: CoverFlowParameters, to pager: FSPagerView) {
    pager.itemSize = cardSize
    pager.isInfinite = suggestions.count > 1
    pager.decelerationDistance = parameters.decelerationValue

    if let adjustable = pager.transformer as? AdjustableCoverFlowTransformer {
      adjustable.parameters = parameters
    } else {
      pager.transformer = AdjustableCoverFlowTransformer(parameters: parameters)
    }
  }

  final class Coordinator: NSObject, FSPagerViewDataSource, FSPagerViewDelegate {
    static let reuseIdentifier = "cover-flow-card"

    var parent: CoverFlowPagerView
    private let imageLoader = RemoteImageLoader()
    var cachedCount: Int = 0

    init(parent: CoverFlowPagerView) {
      self.parent = parent
      self.cachedCount = parent.suggestions.count
    }

    func numberOfItems(in pagerView: FSPagerView) -> Int {
      parent.suggestions.count
    }

    func pagerView(_ pagerView: FSPagerView, cellForItemAt index: Int) -> FSPagerViewCell {
      let cell = pagerView.dequeueReusableCell(withReuseIdentifier: Self.reuseIdentifier, at: index)
      configure(cell: cell, at: index)
      return cell
    }

    private func configure(cell: FSPagerViewCell, at index: Int) {
      cell.contentView.layer.cornerRadius = 22
      cell.contentView.layer.masksToBounds = false
      cell.contentView.layer.shadowColor = UIColor.black.cgColor
      cell.contentView.layer.shadowOpacity = 0.28
      cell.contentView.layer.shadowRadius = 14
      cell.contentView.layer.shadowOffset = CGSize(width: 0, height: 10)

      cell.imageView?.contentMode = .scaleAspectFill
      cell.imageView?.backgroundColor = UIColor.systemGray5
      cell.imageView?.layer.cornerRadius = 22
      cell.imageView?.clipsToBounds = true
      cell.imageView?.image = nil
      cell.tag = index

      guard let url = parent.suggestions[index].posterURL else {
        cell.imageView?.image = UIImage(systemName: "film")
        cell.imageView?.tintColor = UIColor.systemGray2
        return
      }

      imageLoader.loadImage(from: url) { [weak cell] image in
        guard let cell, cell.tag == index else { return }
        cell.imageView?.image = image ?? UIImage(systemName: "film")
        cell.imageView?.tintColor = UIColor.systemGray2
      }
    }

    func pagerViewDidScroll(_ pagerView: FSPagerView) {
      guard parent.currentIndex != pagerView.currentIndex else { return }
      parent.currentIndex = pagerView.currentIndex
    }

    func pagerView(_ pagerView: FSPagerView, didSelectItemAt index: Int) {
      pagerView.deselectItem(at: index, animated: true)
      pagerView.scrollToItem(at: index, animated: true)
    }
  }
}

// MARK: - Transformer

final class AdjustableCoverFlowTransformer: FSPagerViewTransformer {
  var parameters: CoverFlowParameters {
    didSet {
      minimumScale = parameters.cgMinimumScale
      minimumAlpha = parameters.cgMinimumAlpha
      pagerView?.collectionViewLayout.forceInvalidate()
    }
  }

  init(parameters: CoverFlowParameters) {
    self.parameters = parameters
    super.init(type: .coverFlow)
    self.minimumScale = parameters.cgMinimumScale
    self.minimumAlpha = parameters.cgMinimumAlpha
  }

  override func applyTransform(to attributes: FSPagerViewLayoutAttributes) {
    guard let pagerView = pagerView, pagerView.scrollDirection == .horizontal else {
      return
    }

    let clamped = min(max(-attributes.position, -1), 1)
    let baseRotation = sin(clamped * (.pi) * 0.5) * (.pi * 0.25)
    let rotation = baseRotation * parameters.rotationMultiplier
    let itemSpacing = attributes.bounds.width + proposedInteritemSpacing()
    let translationZ = -itemSpacing * parameters.translationMultiplier * abs(clamped)

    var transform3D = CATransform3DIdentity
    transform3D.m34 = -parameters.cgPerspective
    transform3D = CATransform3DRotate(transform3D, rotation, 0, 1, 0)
    let scale = 1 - (1 - parameters.cgMinimumScale) * abs(clamped)
    transform3D = CATransform3DScale(transform3D, scale, scale, 1)
    transform3D = CATransform3DTranslate(transform3D, 0, 0, translationZ)

    attributes.transform3D = transform3D
    attributes.alpha = parameters.cgMinimumAlpha + (1 - parameters.cgMinimumAlpha) * (1 - abs(clamped))
    attributes.zIndex = 100 - Int(abs(clamped) * 80)
  }

  override func proposedInteritemSpacing() -> CGFloat {
    guard let pagerView = pagerView, pagerView.scrollDirection == .horizontal else {
      return 0
    }
    let base = -pagerView.itemSize.width * sin(.pi * 0.25 * 0.25 * 3.0)
    return base * parameters.spacingFactor
  }
}

// MARK: - Debug HUD

#if DEBUG
struct CoverFlowDebugHUD: View {
  @Binding var parameters: CoverFlowParameters
  var onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Text("Cover Flow Tuner")
          .font(.headline)
        Spacer()
        Button("Reset") {
          parameters.reset()
        }
        .font(.caption.weight(.semibold))
        Button {
          onClose()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Close cover flow HUD")
      }
      sliderRow("Card width", value: $parameters.cardWidthRatio, range: 0.48...0.75, format: "%.2f×")
      sliderRow("Spacing", value: $parameters.spacingMultiplier, range: 0.6...1.4, format: "%.2f×")
      sliderRow("Rotation", value: $parameters.rotationFactor, range: 0.8...1.9, format: "%.2f×")
      sliderRow("Depth push", value: $parameters.translationFactor, range: 0.2...0.8, format: "%.2f×")
      sliderRow("Perspective", value: $parameters.perspective, range: 0.001...0.01, format: "%.3f", step: 0.0005)
      sliderRow("Min scale", value: $parameters.minimumScale, range: 0.6...0.95, format: "%.2f")
      sliderRow("Min alpha", value: $parameters.minimumAlpha, range: 0.25...0.8, format: "%.2f")

      Toggle("Adaptive snapping", isOn: $parameters.usesAdaptiveSnapping)
        .font(.caption.weight(.semibold))

      if !parameters.usesAdaptiveSnapping {
        sliderRow("Snap distance", value: $parameters.manualDeceleration, range: 1...4, format: "%.0f cards", step: 1)
      }
    }
    .padding(16)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .shadow(radius: 12)
    .frame(maxWidth: 320)
  }

  private func sliderRow(
    _ label: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    format: String,
    step: Double = 0.01
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label)
          .font(.caption.weight(.semibold))
        Spacer()
        Text(String(format: format, value.wrappedValue))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Slider(value: value, in: range, step: step)
    }
  }
}
#endif

// MARK: - Remote image loader

private final class RemoteImageLoader {
  private let cache = NSCache<NSURL, UIImage>()

  func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
    let key = url as NSURL

    if let cached = cache.object(forKey: key) {
      completion(cached)
      return
    }

    URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
      guard let data, error == nil, let image = UIImage(data: data) else {
        DispatchQueue.main.async { completion(nil) }
        return
      }
      self?.cache.setObject(image, forKey: key)
      DispatchQueue.main.async { completion(image) }
    }.resume()
  }
}
