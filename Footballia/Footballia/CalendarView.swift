import SwiftUI

struct CalendarView: View {
    @Environment(FootballiaService.self) private var service
    @State private var selectedMatch: Match? = nil

    private var monthName: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM"
        var c = DateComponents()
        c.year = service.calendarYear; c.month = service.calendarMonth; c.day = 1
        let date = Calendar.current.date(from: c) ?? Date()
        return df.string(from: date)
    }

    var body: some View {
        ZStack {
            if service.didCheckMasterAccess && !service.hasMasterAccess {
                masterUpsell
            } else {
                calendarBody
            }

            if let match = selectedMatch {
                VideoPlayerOverlay(match: match) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedMatch = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
                .zIndex(10)
            }
        }
        .task {
            let stale = service.isStale("calendar")
            await service.startCalendar(force: stale)
            service.markLoaded("calendar")
        }
    }

    // MARK: - Master gate

    private var masterUpsell: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.15))

            Text("Calendar")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white.opacity(0.7))

            Text("This is a Master feature.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            Text("Sign up for Master access on footballia.eu to browse matches by date — along with many more features.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }

    // MARK: - Calendar

    private var calendarBody: some View {
        VStack(spacing: 0) {
            calendarHeader
            ScrollView {
                VStack(spacing: 28) {
                    monthGrid
                        .padding(.horizontal, 28)
                        .padding(.top, 24)

                    if let day = service.calendarSelectedDay {
                        matchesForDay(day)
                            .padding(.horizontal, 28)
                    } else {
                        Text("Select a highlighted date to see its matches.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 28)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Header

    private var calendarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Calendar")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text("Browse matches by date")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
                if service.isLoadingCalendar {
                    ProgressView().tint(.green).controlSize(.small)
                }
            }

            HStack(spacing: 20) {
                Button { stepMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)

                Text(verbatim: "\(monthName) \(service.calendarYear)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 140, alignment: .center)

                Button { stepMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: - Month grid

    private var monthGrid: some View {
        VStack(spacing: 6) {
            // Day-of-week headers (Monday first)
            HStack(spacing: 0) {
                ForEach(["Mo","Tu","We","Th","Fr","Sa","Su"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            let days = computeDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<days.count, id: \.self) { i in
                    if let day = days[i] {
                        DayCell(
                            day: day,
                            hasMatch: service.calendarMatchDays.contains(day),
                            isSelected: service.calendarSelectedDay == day
                        ) {
                            guard service.calendarMatchDays.contains(day) else { return }
                            service.selectCalendarDay(service.calendarSelectedDay == day ? nil : day)
                        }
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
    }

    // MARK: - Matches for selected day

    @ViewBuilder
    private func matchesForDay(_ day: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(monthName) \(day)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            if let availableAfter = availableAfterDate(day: day) {
                tooRecentBanner(availableAfter: availableAfter)
            } else if service.calendarMatches.isEmpty {
                Text("No matches found for this date.")
                    .foregroundColor(.white.opacity(0.35))
                    .font(.subheadline)
            } else {
                let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 16)]
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(service.calendarMatches) { match in
                        #if os(tvOS)
                        Button { selectedMatch = match } label: {
                            VideoCardView(match: match)
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        #else
                        VideoCardView(match: match)
                            .onTapGesture { selectedMatch = match }
                        #endif
                    }
                }
            }
        }
    }

    private func tooRecentBanner(availableAfter: Date) -> some View {
        let df = DateFormatter()
        df.dateStyle = .long
        return HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.25))
            VStack(alignment: .leading, spacing: 4) {
                Text("Match not yet available")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Text("This match will be available after \(df.string(from: availableAfter)).")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Returns the date on which matches become watchable (game date + 30 days) if the
    /// selected day falls within the 30-day embargo window; nil otherwise.
    private func availableAfterDate(day: Int) -> Date? {
        let cal = Calendar.current
        var c = DateComponents()
        c.year = service.calendarYear; c.month = service.calendarMonth; c.day = day
        guard let gameDate = cal.date(from: c),
              let cutoff = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date()))
        else { return nil }
        guard cal.startOfDay(for: gameDate) >= cutoff else { return nil }
        return cal.date(byAdding: .day, value: 30, to: gameDate)
    }

    // MARK: - Helpers

    private func stepMonth(by delta: Int) {
        var m = service.calendarMonth + delta
        var y = service.calendarYear
        if m < 1  { m = 12; y -= 1 }
        if m > 12 { m = 1;  y += 1 }
        Task { await service.loadCalendar(year: y, month: m) }
    }

    private func computeDays() -> [Int?] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // Monday
        var c = DateComponents()
        c.year = service.calendarYear; c.month = service.calendarMonth; c.day = 1
        guard let first = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }

        let weekday = cal.component(.weekday, from: first)
        // Convert to Monday-based offset (Mon=0 … Sun=6)
        let offset = (weekday + 5) % 7

        var days: [Int?] = Array(repeating: nil, count: offset)
        days += (1...range.count).map { Int?($0) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Int
    let hasMatch: Bool
    let isSelected: Bool
    let onTap: () -> Void
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    private var isHighlighted: Bool { isFocused }
    #else
    @State private var isHovered = false
    private var isHighlighted: Bool { isHovered }
    #endif

    var body: some View {
        Button(action: onTap) {
            Text("\(day)")
                .font(.system(size: 13, weight: hasMatch ? .semibold : .regular))
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasMatch)
        #if !os(tvOS)
        .onHover { isHovered = $0 }
        #endif
        .animation(.easeInOut(duration: 0.12), value: isHighlighted)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private var foreground: Color {
        if isSelected { return .black }
        if hasMatch   { return .green }
        return .white.opacity(0.25)
    }

    private var background: Color {
        if isSelected { return .green }
        if isHighlighted && hasMatch { return .green.opacity(0.18) }
        if hasMatch   { return .green.opacity(0.08) }
        return .clear
    }

    private var borderColor: Color {
        if isSelected { return .clear }
        if hasMatch   { return .green.opacity(isHighlighted ? 0.5 : 0.2) }
        return .clear
    }
}
