import SwiftUI

/// A short first-run introduction. No permission prompts here: notifications and Live
/// Activities are explained when the user first turns them on.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var isCreatingTemplate = false

    var body: some View {
        // Scrolls so every control stays reachable at accessibility text sizes.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RhythmSurface.background)
        .sheet(isPresented: $isCreatingTemplate) {
            NewTemplateSheet { created in
                model.router.selectedTab = .schedule
                model.router.pendingTemplateID = created.id
            }
        }
    }

    private var content: some View {
        VStack(spacing: RhythmSpacing.xxxl) {
            Spacer(minLength: RhythmSpacing.xxxl)

            VStack(spacing: RhythmSpacing.lg) {
                Image(systemName: "metronome")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Your day, in rhythm.")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Set up your class schedule once. Rhythm shows what’s happening now, how long is left, and what’s next — in the app, on your Home Screen, and on your Lock Screen.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: RhythmSpacing.lg) {
                FeatureRow(symbol: "clock", title: "Live countdown", detail: "The current period and time remaining, always accurate.")
                FeatureRow(symbol: "calendar.badge.clock", title: "Special days", detail: "Late starts, assemblies, and holidays without rebuilding your week.")
                FeatureRow(symbol: "lock.shield", title: "Private", detail: "Everything stays on this iPhone. No account needed.")
            }

            Spacer(minLength: RhythmSpacing.lg)

            VStack(spacing: RhythmSpacing.md) {
                Button {
                    isCreatingTemplate = true
                } label: {
                    Text("Set Up My Schedule")
                        .frame(maxWidth: .infinity, minHeight: RhythmLayout.minimumTouchTarget)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("setUpScheduleButton")

                Button {
                    model.insertSample()
                    model.preferences.hasCompletedOnboarding = true
                } label: {
                    Text("Explore a Sample")
                        .frame(maxWidth: .infinity, minHeight: RhythmLayout.minimumTouchTarget)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("exploreSampleButton")
            }
        }
        .padding(.horizontal, RhythmSpacing.xxl)
        .padding(.bottom, RhythmSpacing.xxl)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: RhythmSpacing.lg) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
