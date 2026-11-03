"""Generate Dart classifier parity fixtures from the unchanged Python rules.

Run from the repository root:
    python mobile/tool/generate_classifier_fixtures.py
"""

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from app.services.organization import classify_document  # noqa: E402

CASES = [
    {
        "name": "finance_invoice",
        "filename": "invoice_2024.pdf",
        "text": "Invoice\nBill to: Acme Corp\nAmount due: 100.00\nSubtotal: 90.00\nInvoice number: INV-2024-001",
    },
    {
        "name": "education_transcript",
        "filename": "spring_semester.pdf",
        "text": "Official transcript\nUniversity of Example\nStudent: Jane Doe\nSemester: Spring 2024\nCourse grade report",
    },
    {
        "name": "health_record",
        "filename": "clinic_visit.pdf",
        "text": "Medical record\nPatient: Jane Doe\nDiagnosis: seasonal allergy\nPrescription dosage: 10 mg\nPhysician: Dr. Smith",
    },
    {
        "name": "identity_passport",
        "filename": "identity.pdf",
        "text": "Passport\nIdentity card\nBirth certificate\nNational id: 123456789",
    },
    {
        "name": "home_lease",
        "filename": "lease_2024.pdf",
        "text": "Lease agreement\nLandlord: Example Holdings\nTenant: Jane Doe\nUtility bill\nElectricity bill for April",
    },
    {
        "name": "appliances_manual",
        "filename": "fridge_manual.pdf",
        "text": "User manual\nRefrigerator model number: RF-900\nSerial number: SN-778812\nWarranty card enclosed",
    },
    {
        "name": "insurance_policy",
        "filename": "policy_2024.pdf",
        "text": "Insurance policy\nPolicy number: POL-2024-0042\nAnnual premium: 240.00\nCoverage: comprehensive\nDeductible: 500\nIssued by: Northwind Assurance",
    },
    {
        "name": "travel_itinerary",
        "filename": "trip.pdf",
        "text": "Travel itinerary\nAirline: Example Air\nFlight: EA-220\nBoarding pass\nHotel reservation confirmation",
    },
    {
        "name": "work_employment",
        "filename": "offer_letter.pdf",
        "text": "Employment offer\nEmployer: Acme Corp\nSalary: 42000\nPay stub\nPayslip\nJob offer accepted",
    },
    {
        "name": "legal_contract",
        "filename": "nda.pdf",
        "text": "Non-disclosure agreement\nThis contract is between the parties.\nCourt: Example District\nAttorney: Jane Doe\nTerms and conditions apply.",
    },
    {
        "name": "uncategorized",
        "filename": "notes.txt",
        "text": "Remember to buy milk and call the plumber on Tuesday.",
    },
    {
        "name": "empty_text",
        "filename": "scan.pdf",
        "text": "",
    },
    {
        "name": "tie_insurance_wins_by_order",
        "filename": "mixed.pdf",
        "text": "insurance contract",
    },
    {
        "name": "tie_finance_wins_by_order",
        "filename": "mixed2.pdf",
        "text": "receipt agreement",
    },
    {
        "name": "date_iso",
        "filename": "dated.pdf",
        "text": "Invoice\nIssued 2024-03-15\nAmount due: 10.00",
    },
    {
        "name": "date_month_name",
        "filename": "dated2.pdf",
        "text": "Receipt\nPaid on March 7th, 2023\nAmount due: 10.00",
    },
    {
        "name": "date_day_month_name",
        "filename": "dated3.pdf",
        "text": "Receipt\nPaid on 7 March 2023\nAmount due: 10.00",
    },
    {
        "name": "date_numeric_day_first",
        "filename": "dated4.pdf",
        "text": "Receipt\nPaid on 25/03/2024\nAmount due: 10.00",
    },
    {
        "name": "date_numeric_ambiguous",
        "filename": "dated5.pdf",
        "text": "Receipt\nPaid on 03/04/2024\nAmount due: 10.00",
    },
    {
        "name": "date_invalid_then_valid",
        "filename": "dated6.pdf",
        "text": "Receipt\nPaid on 2024-13-01 or 2024-12-01\nAmount due: 10.00",
    },
    {
        "name": "issuer_and_reference",
        "filename": "reference.pdf",
        "text": "Prepared by: Example Accounting\nClaim number: CLM-9911\namount due: 12.00",
    },
    {
        "name": "existing_tags",
        "filename": "receipt.txt",
        "text": "Purchase receipt\nTransaction total: 9.99",
        "existing_tags": ["personal", "receipt"],
    },
    {
        "name": "case_insensitive",
        "filename": "UPPER.PDF",
        "text": "BANK STATEMENT\nACCOUNT STATEMENT\nTRANSACTION HISTORY",
    },
    {
        "name": "title_fallback_to_filename",
        "filename": "short_term_rental-agreement.pdf",
        "text": "2024-01-01\n2024-02-01",
    },
]


def expected(text: str, filename: str, existing_tags: list[str]) -> dict:
    result = classify_document(
        filename=filename,
        extracted_text=text or None,
        existing_tags=existing_tags,
    )
    return {
        "category": result.category,
        "confidence": result.confidence,
        "reasons": result.reasons,
        "method": result.method,
        "document_title": result.document_title,
        "document_type": result.document_type,
        "document_date": result.document_date.isoformat()
        if result.document_date
        else None,
        "issuer": result.issuer,
        "reference_number": result.reference_number,
        "tags": result.tags,
    }


def main() -> None:
    output = []
    for case in CASES:
        tags = case.get("existing_tags", [])
        output.append(
            {
                "name": case["name"],
                "filename": case["filename"],
                "text": case["text"],
                "existing_tags": tags,
                "expected": expected(case["text"], case["filename"], tags),
            }
        )

    destination = ROOT / "mobile/test/local/fixtures/classifier_parity.json"
    destination.write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(output)} fixtures to {destination}")


if __name__ == "__main__":
    main()
