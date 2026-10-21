// LuminaVaultClient/LuminaVaultClientTests/CalendarAttendeeMappingTests.swift
//
// EventKit attendees → the calendar sync's `attendees`: `mailto:` parsing,
// missing names, the user's own entry, duplicates, the cap, and the
// nil-means-nobody rule that keeps a cleared guest list cleared.

import Foundation
import LuminaVaultShared
import Testing

@testable import LuminaVaultClient

struct CalendarAttendeeMappingTests {
    private func participant(_ name: String?, _ url: String?, me: Bool = false) -> CalendarParticipant {
        CalendarParticipant(name: name, url: url.flatMap(URL.init(string:)), isCurrentUser: me)
    }

    @Test
    func `a named participant with a mailto URL sends both`() {
        let attendees = CalendarAttendeeMapping.attendees(from: [participant("Ana Silva", "mailto:ana@example.com")])
        #expect(attendees == [CalendarAttendeeDTO(name: "Ana Silva", email: "ana@example.com")])
    }

    @Test
    func `no attendees is an empty list, not an omitted one`() {
        // EventKit says "nobody" with nil; sending nil would keep the old list.
        #expect(CalendarAttendeeMapping.attendees(from: nil) == [])
        #expect(CalendarAttendeeMapping.attendees(from: []) == [])
    }

    @Test
    func `a participant without a name keeps the email`() {
        let attendees = CalendarAttendeeMapping.attendees(from: [
            participant(nil, "mailto:rui@example.com"),
            participant("   ", "mailto:joana@example.com"),
        ])
        #expect(attendees == [
            CalendarAttendeeDTO(name: nil, email: "rui@example.com"),
            CalendarAttendeeDTO(name: nil, email: "joana@example.com"),
        ])
    }

    @Test
    func `a participant without an email keeps the name`() {
        let attendees = CalendarAttendeeMapping.attendees(from: [
            participant("Room 4.2", nil),
            participant("Marta", "urn:uuid:7c1b1f4e-0000-4000-8000-000000000001"),
            participant("Pedro", "https://example.com/pedro"),
        ])
        #expect(attendees == [
            CalendarAttendeeDTO(name: "Room 4.2", email: nil),
            CalendarAttendeeDTO(name: "Marta", email: nil),
            CalendarAttendeeDTO(name: "Pedro", email: nil),
        ])
    }

    @Test
    func `a participant with neither is dropped`() {
        let attendees = CalendarAttendeeMapping.attendees(from: [
            participant(nil, nil),
            participant("", "urn:uuid:1"),
            participant(nil, "mailto:"),
        ])
        #expect(attendees.isEmpty)
    }

    @Test(arguments: [
        ("mailto:ana@example.com", "ana@example.com"),
        ("MAILTO:ana@example.com", "ana@example.com"),
        ("mailto:ana@example.com?subject=Hello", "ana@example.com"),
        ("mailto:ana%2Bwork@example.com", "ana+work@example.com"),
        ("mailto:%20ana@example.com", "ana@example.com"),
    ])
    func `mailto URLs give the address`(raw: String, expected: String) throws {
        let url = try #require(URL(string: raw))
        #expect(CalendarAttendeeMapping.email(from: url) == expected)
    }

    @Test(arguments: [
        "https://example.com/ana@example.com",
        "urn:uuid:7c1b1f4e-0000-4000-8000-000000000001",
        "mailto:not-an-address",
    ])
    func `other URLs are not emails`(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(CalendarAttendeeMapping.email(from: url) == nil)
    }

    @Test
    func `the user's own entry is left out`() {
        let attendees = CalendarAttendeeMapping.attendees(from: [
            participant("Fernando", "mailto:me@example.com", me: true),
            participant("Ana", "mailto:ana@example.com"),
        ])
        #expect(attendees == [CalendarAttendeeDTO(name: "Ana", email: "ana@example.com")])
    }

    @Test
    func `one person listed twice is sent once`() {
        let attendees = CalendarAttendeeMapping.attendees(from: [
            participant("Ana", "mailto:ana@example.com"),
            participant("Ana Silva", "mailto:ANA@example.com"),
            participant("Rui", nil),
            participant("rui", nil),
        ])
        #expect(attendees == [
            CalendarAttendeeDTO(name: "Ana", email: "ana@example.com"),
            CalendarAttendeeDTO(name: "Rui", email: nil),
        ])
    }

    @Test
    func `at most a hundred are sent, in order`() {
        let many = (0..<150).map { participant("Guest \($0)", "mailto:guest\($0)@example.com") }
        let attendees = CalendarAttendeeMapping.attendees(from: many)
        #expect(attendees.count == CalendarAttendeeMapping.maxAttendees)
        #expect(attendees.first?.name == "Guest 0")
        #expect(attendees.last?.name == "Guest 99")
    }

    @Test
    func `the sync input encodes attendees, and an empty list as an array`() throws {
        let start = Date(timeIntervalSince1970: 1_792_400_000)
        let input = AppleCalendarEventInput(
            externalID: "e1",
            title: "1:1",
            startsAt: start,
            endsAt: start.addingTimeInterval(1800),
            attendees: CalendarAttendeeMapping.attendees(from: nil)
        )
        let json = try #require(String(bytes: try JSONEncoder().encode(input), encoding: .utf8))
        #expect(json.contains(#""attendees":[]"#))
    }
}
