//
//  ListeningStatsView.swift
//  PodcastAnalyzer
//
//  Listening statistics view with charts and summary cards
//

import Charts
import SwiftData
import SwiftUI

struct ListeningStatsView: View {
  @State private var viewModel = ListeningStatsViewModel()
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        // Time period picker
        timePeriodPicker

        if viewModel.isLoading {
          ProgressView("Loading stats...")
            .padding(.top, 40)
        } else if viewModel.totalEpisodesPlayed == 0 {
          emptyState
        } else {
          // Summary cards
          summaryCards

          // Streak card
          if viewModel.longestStreakDays > 1 {
            streakCard
          }

          // Weekly listening chart
          if viewModel.weeklyBuckets.count > 1 {
            weeklyChart
          }

          // Top Shows chart
          if !viewModel.topPodcasts.isEmpty {
            topShowsChart

            // Ranked list
            topShowsList
          }
        }
      }
      .padding()
    }
    .navigationTitle("Listening Stats")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
    .onChange(of: viewModel.selectedTimePeriod) { _, _ in
      viewModel.loadStats()
    }
  }

  // MARK: - Time Period Picker

  private var timePeriodPicker: some View {
    Picker("Time Period", selection: $viewModel.selectedTimePeriod) {
      ForEach(TimePeriod.allCases) { period in
        Text(period.displayName).tag(period)
      }
    }
    .pickerStyle(.segmented)
  }

  // MARK: - Summary Cards

  private var summaryCards: some View {
    HStack(spacing: 12) {
      StatCard(
        title: "Hours Listened",
        value: String(format: "%.1f", viewModel.totalHoursListened),
        icon: "headphones",
        color: .indigo
      )

      StatCard(
        title: "Episodes Played",
        value: "\(viewModel.totalEpisodesPlayed)",
        icon: "play.circle.fill",
        color: .blue
      )
    }
  }

  // MARK: - Streak Card

  private var streakCard: some View {
    HStack {
      Image(systemName: "flame.fill")
        .foregroundStyle(.orange)
      Text("Longest streak: **\(viewModel.longestStreakDays) days**")
        .font(.subheadline)
      Spacer()
    }
    .padding(12)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
  }

  // MARK: - Weekly Chart

  private var weeklyChart: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Hours per Week")
        .font(.headline)

      Chart(viewModel.weeklyBuckets) { bucket in
        BarMark(
          x: .value("Week", bucket.weekStart, unit: .weekOfYear),
          y: .value("Hours", bucket.hours)
        )
        .foregroundStyle(Color.indigo.gradient)
        .cornerRadius(3)
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .month)) { _ in
          AxisGridLine()
          AxisValueLabel(format: .dateTime.month(.abbreviated))
        }
      }
      .chartYAxis {
        AxisMarks { value in
          AxisGridLine()
          AxisValueLabel("\(value.as(Double.self).map { String(format: "%.0fh", $0) } ?? "")")
        }
      }
      .frame(height: 160)
    }
    .padding()
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
  }

  // MARK: - Top Shows Chart

  private var topShowsChart: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Top Shows")
        .font(.headline)

      Chart(viewModel.topPodcasts) { stat in
        BarMark(
          x: .value("Hours", stat.totalHours),
          y: .value("Podcast", stat.podcastTitle)
        )
        .foregroundStyle(.indigo.gradient)
        .cornerRadius(4)
        .annotation(position: .trailing, spacing: 4) {
          Text(String(format: "%.1fh", stat.totalHours))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .chartYAxis {
        AxisMarks { value in
          AxisValueLabel {
            if let title = value.as(String.self) {
              Text(title)
                .font(.caption)
                .lineLimit(1)
            }
          }
        }
      }
      .chartXAxis {
        AxisMarks { value in
          AxisGridLine()
          AxisValueLabel {
            if let hours = value.as(Double.self) {
              Text(String(format: "%.0fh", hours))
                .font(.caption2)
            }
          }
        }
      }
      .frame(height: CGFloat(viewModel.topPodcasts.count) * 60)
    }
    .padding(16)
    .glassEffect(.regular, in: .rect(cornerRadius: 12))
  }

  // MARK: - Top Shows List

  private var topShowsList: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(viewModel.topPodcasts.enumerated()), id: \.element.id) { index, stat in
        HStack(spacing: 12) {
          // Rank
          Text("\(index + 1)")
            .font(.title2)
            .bold()
            .foregroundStyle(.secondary)
            .frame(width: 28)

          // Artwork
          CachedArtworkImage(urlString: stat.imageURL, size: 44, cornerRadius: 8)

          // Info
          VStack(alignment: .leading, spacing: 2) {
            Text(stat.podcastTitle)
              .font(.subheadline)
              .fontWeight(.medium)
              .lineLimit(1)

            HStack(spacing: 8) {
              Label("\(stat.playCount) episodes", systemImage: "play.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

              Label(String(format: "%.1fh", stat.totalHours), systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer()
        }
        .padding(.vertical, 4)

        if index < viewModel.topPodcasts.count - 1 {
          Divider()
        }
      }
    }
    .padding(16)
    .glassEffect(.regular, in: .rect(cornerRadius: 12))
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "chart.bar")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      Text("No Listening Data")
        .font(.headline)

      Text("Start listening to episodes to see your stats here")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }
}

// MARK: - Stat Card

private struct StatCard: View {
  let title: String
  let value: String
  let icon: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .foregroundStyle(color)
        Spacer()
      }

      Text(value)
        .font(.title)
        .bold()

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular, in: .rect(cornerRadius: 12))
  }
}
