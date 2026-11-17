// Guardian escalation engine: notifier interface + safe implementations.
//
// A Notifier delivers an escalation alert to ONE kin contact and reports
// whether the message was handed off. Acknowledgment ("I am responding")
// arrives out of band (reply SMS, app tap, voice keypress) and is fed
// back into the engine via engine.acknowledge(contactId); a notifier
// does NOT decide acknowledgment itself.
//
// Interface (duck-typed):
//   async notify(contact, alert) -> { delivered: boolean, channel: string }
//     contact: { id: string, name: string, phone?: string }
//     alert:   { episodeId, triggerType, message, location? }
//
// NO real messaging happens in this scaffold. Twilio wiring belongs
// behind this interface in a later, separately reviewed step, with
// credentials supplied from the environment at runtime only.

'use strict';

class ConsoleNotifier {
  async notify(contact, alert) {
    // eslint-disable-next-line no-console
    console.log(
      `[guardian:notifier] -> ${contact.name} (${contact.id}): ${alert.message}`
    );
    return { delivered: true, channel: 'console' };
  }
}

class MockNotifier {
  constructor() {
    /** @type {Array<{contact: object, alert: object}>} */
    this.calls = [];
  }

  async notify(contact, alert) {
    this.calls.push({ contact, alert });
    return { delivered: true, channel: 'mock' };
  }
}

module.exports = { ConsoleNotifier, MockNotifier };
