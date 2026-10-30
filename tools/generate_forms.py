"""Generate the fillable PDF forms of the onboarding packet.

The forms are fictitious. The bank, the form codes and the wording are invented
for the demo. Each form has text fields, check boxes, radio buttons, date fields
(with a date format, so the viewer shows a date picker) and signature fields.
Required fields carry the PDF "Required" flag, which the app reads to check the
form before signing.

Usage:
    python tools/generate_forms.py [output-folder]

Default output folder: OnboardingPacket/Forms
"""

import io
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import (
    ArrayObject,
    DictionaryObject,
    FloatObject,
    NameObject,
    NumberObject,
    TextStringObject,
)
from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER
from reportlab.pdfgen import canvas

BANK = "Quillmere Savings Bank"
PAGE_W, PAGE_H = LETTER
MARGIN = 54
CONTENT_W = PAGE_W - 2 * MARGIN
DATE_FORMAT = "yyyy-mm-dd"

INK = colors.HexColor("#1f2933")
MUTED = colors.HexColor("#616e7c")
RULE = colors.HexColor("#cbd2d9")
BAND = colors.HexColor("#e4e7eb")
FIELD_BORDER = colors.HexColor("#9aa5b1")


class FormBuilder:
    """Draws a form page by page and records the fields that reportlab cannot create."""

    def __init__(self, title, code, intro):
        self.buffer = io.BytesIO()
        self.c = canvas.Canvas(self.buffer, pagesize=LETTER)
        self.c.setTitle(title)
        self.c.setAuthor(BANK + " (fictitious)")
        self.c.setSubject("Fictitious sample form for a demo")
        self.title = title
        self.code = code
        self.intro = intro
        self.page = 0
        self.y = 0
        self.date_fields = []
        self.signature_fields = []  # (page index, name, label, rect, required)
        self._start_page()

    # Page structure ---------------------------------------------------

    def _start_page(self):
        c = self.c
        c.setFillColor(BAND)
        c.rect(0, PAGE_H - 78, PAGE_W, 78, stroke=0, fill=1)
        c.setFillColor(INK)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(MARGIN, PAGE_H - 30, BANK.upper())
        c.setFont("Helvetica-Bold", 17)
        c.drawString(MARGIN, PAGE_H - 54, self.title)
        c.setFont("Helvetica", 9)
        c.setFillColor(MUTED)
        c.drawRightString(PAGE_W - MARGIN, PAGE_H - 30, "Form " + self.code)
        c.drawRightString(PAGE_W - MARGIN, PAGE_H - 54, "Fields marked * are required")
        self.y = PAGE_H - 100
        if self.page == 0 and self.intro:
            c.setFont("Helvetica", 9.5)
            c.setFillColor(INK)
            for line in self.intro:
                c.drawString(MARGIN, self.y, line)
                self.y -= 13
            self.y -= 6

    def _footer(self, total):
        c = self.c
        c.setStrokeColor(RULE)
        c.line(MARGIN, 40, PAGE_W - MARGIN, 40)
        c.setFont("Helvetica", 8)
        c.setFillColor(MUTED)
        c.drawString(MARGIN, 28, "Fictitious sample form created for a software demo. Not a real bank or product.")
        c.drawRightString(PAGE_W - MARGIN, 28, "Page %d of %d" % (self.page + 1, total))

    def new_page(self, total):
        self._footer(total)
        self.c.showPage()
        self.page += 1
        self._start_page()

    def section(self, text):
        c = self.c
        self.y -= 8
        c.setFillColor(INK)
        c.setFont("Helvetica-Bold", 11.5)
        c.drawString(MARGIN, self.y, text)
        c.setStrokeColor(RULE)
        c.setLineWidth(0.8)
        c.line(MARGIN, self.y - 5, PAGE_W - MARGIN, self.y - 5)
        self.y -= 24

    def note(self, text):
        self.c.setFont("Helvetica-Oblique", 8.5)
        self.c.setFillColor(MUTED)
        self.c.drawString(MARGIN, self.y, text)
        self.y -= 16

    # Fields -----------------------------------------------------------

    def _label(self, x, y, label, required):
        self.c.setFont("Helvetica", 8.5)
        self.c.setFillColor(MUTED)
        self.c.drawString(x, y, label + (" *" if required else ""))

    def text_row(self, fields, height=22):
        """fields: list of (name, label, width fraction, required, kind) on one row."""
        gap = 12
        usable = CONTENT_W - gap * (len(fields) - 1)
        x = MARGIN
        for name, label, frac, required, kind in fields:
            w = usable * frac
            self._label(x, self.y, label, required)
            self.c.acroForm.textfield(
                name=name,
                tooltip=label,
                x=x,
                y=self.y - 4 - height,
                width=w,
                height=height,
                fontName="Helvetica",
                fontSize=10,
                borderStyle="solid",
                borderColor=FIELD_BORDER,
                fillColor=colors.white,
                textColor=INK,
                borderWidth=0.8,
                fieldFlags="required" if required else "",
                maxlen=120,
            )
            if kind == "date":
                self.date_fields.append(name)
                self.c.setFont("Helvetica", 7.5)
                self.c.setFillColor(MUTED)
                self.c.drawRightString(x + w, self.y, DATE_FORMAT.upper())
            x += w + gap
        self.y -= height + 22

    def checkbox(self, name, text, required, sub=None):
        self.c.acroForm.checkbox(
            name=name,
            tooltip=text,
            x=MARGIN,
            y=self.y - 4,
            size=14,
            buttonStyle="check",
            borderColor=FIELD_BORDER,
            fillColor=colors.white,
            textColor=INK,
            borderWidth=0.8,
            fieldFlags="required" if required else "",
        )
        self.c.setFont("Helvetica", 9.5)
        self.c.setFillColor(INK)
        self.c.drawString(MARGIN + 22, self.y, text + (" *" if required else ""))
        if sub:
            self.c.setFont("Helvetica", 8)
            self.c.setFillColor(MUTED)
            self.c.drawString(MARGIN + 22, self.y - 11, sub)
            self.y -= 10
        self.y -= 24

    def radio_group(self, name, label, options, required, columns=3):
        self._label(MARGIN, self.y, label, required)
        self.y -= 20
        col_w = CONTENT_W / columns
        for i, (value, text) in enumerate(options):
            col = i % columns
            if i and col == 0:
                self.y -= 22
            x = MARGIN + col * col_w
            self.c.acroForm.radio(
                name=name,
                tooltip=label,
                value=value,
                selected=False,
                x=x,
                y=self.y - 4,
                size=14,
                buttonStyle="circle",
                borderColor=FIELD_BORDER,
                fillColor=colors.white,
                textColor=INK,
                borderWidth=0.8,
                fieldFlags="noToggleToOff radio" + (" required" if required else ""),
            )
            self.c.setFont("Helvetica", 9.5)
            self.c.setFillColor(INK)
            self.c.drawString(x + 20, self.y, text)
        self.y -= 30

    def signature_row(self, specs, height=58):
        """specs: list of (signature name, label, date name, date label)."""
        gap = 24
        w = (CONTENT_W - gap * (len(specs) - 1)) / len(specs)
        x = MARGIN
        for sig_name, sig_label, date_name, date_label in specs:
            self._label(x, self.y, sig_label, True)
            rect = (x, self.y - 4 - height, x + w, self.y - 4)
            self.c.setStrokeColor(FIELD_BORDER)
            self.c.setLineWidth(0.8)
            self.c.setDash(3, 2)
            self.c.rect(rect[0], rect[1], w, height, stroke=1, fill=0)
            self.c.setDash()
            self.c.setFont("Helvetica", 7.5)
            self.c.setFillColor(MUTED)
            self.c.drawString(x + 6, rect[1] + 6, "Sign inside the box")
            self.signature_fields.append((self.page, sig_name, sig_label, rect, True))
            x += w + gap
        self.y -= height + 24
        x = MARGIN
        row = []
        for _, _, date_name, date_label in specs:
            row.append((date_name, date_label, 1 / len(specs), True, "date"))
        self.text_row(row)

    def finish(self, total):
        self._footer(total)
        self.c.save()
        return self.buffer.getvalue()


def add_dates_and_signatures(pdf_bytes, builder):
    """Adds date formats and signature fields with pypdf (reportlab has no signature field)."""
    reader = PdfReader(io.BytesIO(pdf_bytes))
    writer = PdfWriter(clone_from=reader)
    acroform = writer._root_object["/AcroForm"]
    fields = acroform["/Fields"]

    # Date format: the viewer formats the value and offers a date picker.
    for field_ref in fields:
        field = field_ref.get_object()
        if field.get("/T") in builder.date_fields:
            fmt = DictionaryObject({
                NameObject("/S"): NameObject("/JavaScript"),
                NameObject("/JS"): TextStringObject('AFDate_FormatEx("%s");' % DATE_FORMAT),
            })
            keystroke = DictionaryObject({
                NameObject("/S"): NameObject("/JavaScript"),
                NameObject("/JS"): TextStringObject('AFDate_KeystrokeEx("%s");' % DATE_FORMAT),
            })
            field[NameObject("/AA")] = DictionaryObject({
                NameObject("/F"): writer._add_object(fmt),
                NameObject("/K"): writer._add_object(keystroke),
            })

    for page_index, name, label, rect, required in builder.signature_fields:
        page = writer.pages[page_index]
        sig = DictionaryObject({
            NameObject("/Type"): NameObject("/Annot"),
            NameObject("/Subtype"): NameObject("/Widget"),
            NameObject("/FT"): NameObject("/Sig"),
            NameObject("/T"): TextStringObject(name),
            NameObject("/TU"): TextStringObject(label),
            NameObject("/Rect"): ArrayObject([FloatObject(v) for v in rect]),
            NameObject("/F"): NumberObject(4),
            NameObject("/Ff"): NumberObject(2 if required else 0),
            NameObject("/P"): page.indirect_reference,
        })
        ref = writer._add_object(sig)
        if "/Annots" not in page:
            page[NameObject("/Annots")] = ArrayObject()
        page["/Annots"].append(ref)
        fields.append(ref)

    acroform[NameObject("/SigFlags")] = NumberObject(1)
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


def account_opening():
    b = FormBuilder(
        "Account Opening Application",
        "QSB-AO-01",
        [
            "Use this form to open a personal account. Complete every required field before you sign.",
            "The branch adviser or field agent checks the form with you.",
        ],
    )
    total = 2
    b.section("1. Personal details")
    b.text_row([
        ("title", "Title", 0.16, False, "text"),
        ("first_name", "First name", 0.42, True, "text"),
        ("last_name", "Last name", 0.42, True, "text"),
    ])
    b.text_row([
        ("date_of_birth", "Date of birth", 0.34, True, "date"),
        ("nationality", "Nationality", 0.33, True, "text"),
        ("mobile_phone", "Mobile phone", 0.33, True, "text"),
    ])
    b.text_row([("email", "Email address", 1.0, True, "text")])
    b.section("2. Residential address")
    b.text_row([("address_line1", "Address line 1", 1.0, True, "text")])
    b.text_row([("address_line2", "Address line 2", 1.0, False, "text")])
    b.text_row([
        ("city", "City", 0.45, True, "text"),
        ("postal_code", "Postal code", 0.2, True, "text"),
        ("country", "Country", 0.35, True, "text"),
    ])
    b.section("3. Employment")
    b.radio_group(
        "employment_status",
        "Employment status",
        [("Employed", "Employed"), ("SelfEmployed", "Self-employed"), ("Retired", "Retired"),
         ("Student", "Student"), ("NotEmployed", "Not employed")],
        True,
    )
    b.text_row([
        ("occupation", "Occupation", 0.5, True, "text"),
        ("employer", "Employer", 0.5, False, "text"),
    ])
    b.new_page(total)

    b.section("4. Account")
    b.radio_group(
        "account_type",
        "Account type",
        [("Current", "Everyday current account"), ("InstantSavings", "Instant access savings"),
         ("FixedSavings", "Fixed-term savings")],
        True,
    )
    b.text_row([
        ("initial_deposit", "Initial deposit (USD)", 0.35, True, "text"),
        ("source_of_funds", "Source of funds", 0.65, True, "text"),
    ])
    b.checkbox("debit_card", "Issue a debit card", False)
    b.checkbox("online_banking", "Register for online and mobile banking", False)
    b.checkbox("paper_statements", "Send paper statements by post", False)
    b.section("5. Tax residency")
    b.text_row([
        ("tax_country", "Country of tax residence", 0.5, True, "text"),
        ("tax_id", "Tax identification number", 0.5, False, "text"),
    ])
    b.section("6. Declaration")
    b.checkbox("declaration_true", "I confirm that the information in this application is true and complete.", True)
    b.checkbox("terms_accepted", "I have received and accept the account terms and conditions.", True,
               sub="Account terms version 4.1, fee schedule and deposit protection information sheet.")
    b.signature_row([("customer_signature", "Customer signature", "signature_date", "Date")])
    return add_dates_and_signatures(b.finish(total), b)


def consent():
    b = FormBuilder(
        "Privacy and Communications Consent",
        "QSB-PC-02",
        [
            "We use your personal data to open and run your account, as described in our privacy notice.",
            "Marketing preferences are optional. You can change them at any time.",
        ],
    )
    total = 1
    b.section("1. Customer")
    b.text_row([
        ("full_name", "Full name", 0.65, True, "text"),
        ("customer_reference", "Customer reference (bank use)", 0.35, False, "text"),
    ])
    b.section("2. Required consents")
    b.checkbox("privacy_notice_read", "I have read the privacy notice (version 3.2).", True)
    b.checkbox("identity_check", "I agree to an identity and fraud prevention check.", True,
               sub="The check is run with a credit reference agency. It leaves a soft search on your file.")
    b.section("3. Marketing preferences (optional)")
    b.checkbox("marketing_email", "Send me product news by email", False)
    b.checkbox("marketing_sms", "Send me offers by text message", False)
    b.checkbox("marketing_phone", "Contact me by phone about savings rates", False)
    b.checkbox("partner_offers", "Share my contact details with selected insurance partners", False)
    b.section("4. Signature")
    b.signature_row([("consent_signature", "Customer signature", "consent_date", "Date")])
    return add_dates_and_signatures(b.finish(total), b)


def identity_verification():
    b = FormBuilder(
        "Identity Verification Record",
        "QSB-IV-03",
        [
            "Completed by the branch adviser or field agent who sees the original documents.",
            "The customer and the staff member both sign.",
        ],
    )
    total = 1
    b.section("1. Customer")
    b.text_row([("customer_name", "Customer full name", 1.0, True, "text")])
    b.section("2. Identity document")
    b.radio_group(
        "id_document_type",
        "Document type",
        [("Passport", "Passport"), ("NationalId", "National identity card"), ("DrivingLicence", "Driving licence")],
        True,
    )
    b.text_row([
        ("id_document_number", "Document number", 0.4, True, "text"),
        ("id_issuing_country", "Issuing country", 0.3, True, "text"),
        ("id_expiry_date", "Expiry date", 0.3, True, "date"),
    ])
    b.section("3. Proof of address")
    b.radio_group(
        "address_proof",
        "Document seen",
        [("UtilityBill", "Utility bill"), ("BankStatement", "Bank statement"), ("TaxLetter", "Tax letter")],
        True,
    )
    b.section("4. Verification")
    b.radio_group(
        "verification_channel",
        "Where the documents were seen",
        [("Branch", "In a branch"), ("FieldVisit", "Field visit at the customer's address")],
        True,
        columns=2,
    )
    b.text_row([
        ("staff_name", "Staff member name", 0.65, True, "text"),
        ("staff_id", "Staff ID", 0.35, True, "text"),
    ])
    b.checkbox("originals_seen", "I have seen the original documents and they match the customer.", True)
    b.signature_row([
        ("verification_customer_signature", "Customer signature", "verification_date", "Date"),
        ("staff_signature", "Staff member signature", "staff_signature_date", "Date"),
    ])
    return add_dates_and_signatures(b.finish(total), b)


def main():
    root = Path(__file__).resolve().parent.parent
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "OnboardingPacket" / "Forms"
    out_dir.mkdir(parents=True, exist_ok=True)
    forms = {
        "account-opening-application.pdf": account_opening(),
        "privacy-and-communications-consent.pdf": consent(),
        "identity-verification-record.pdf": identity_verification(),
    }
    for name, data in forms.items():
        (out_dir / name).write_bytes(data)
        print("wrote %s (%d bytes)" % (out_dir / name, len(data)))


if __name__ == "__main__":
    main()
