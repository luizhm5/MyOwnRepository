# InvoiceExport Application Documentation

## Overview

The InvoiceExport application is a Laravel-based web application that integrates with Salesforce to provide various export functionalities for invoices and related data. It allows users to export data in Excel format, which is then stored in Google Drive (previously used Box.com as indicated by some legacy code).

## System Requirements

- Apache server >= 2.4.0
- MySQL server >= 5.7.0
- PHP >= 8.2

## Application Architecture

The application follows the Laravel framework's MVC architecture:

- **Models**: Handle data interaction and business logic
- **Controllers**: Process requests and manage application flow
- **Views**: Present data to users
- **Jobs**: Handle background processing tasks

### Key Components

1. **Controllers**
   - `SalesforceController`: Handles Salesforce Canvas integration and initiates export processes
   - `ProcessController`: Manages the export process interface and authorization

2. **Models**
   - `BaseSalesforceProvider`: Base class for Salesforce API integration
   - `SFBillingProvider`: Handles invoice export data retrieval from Salesforce
   - `SFHistoryProvider`: Handles history export data retrieval from Salesforce
   - `SFPfxProvider`: Handles PFX export data retrieval from Salesforce
   - `SignedRequest`: Validates and processes Salesforce Canvas signed requests
   - `FileHelper`: Interface for file storage operations
   - `GoogleDriveHelper`: Implements FileHelper for Google Drive storage

3. **Jobs (Background Processing)**
   - `InvoiceExportJob`: Processes invoice export requests asynchronously
   - `HistoryExportJob`: Processes history export requests asynchronously
   - `PfxExportJob`: Processes PFX export requests asynchronously

## Main Functionality

### 1. Salesforce Canvas Integration

The application integrates with Salesforce using the Canvas framework:

- Users initiate exports from within Salesforce
- Salesforce sends a signed request to the application
- `SignedRequest` class validates the request using the appropriate consumer secret
- User is authenticated based on the Salesforce signed request

### 2. Export Types

#### Invoice Export
- Exports invoice data based on billing period, status, and search criteria
- Creates Excel files with invoice data
- Supports "final" invoice exports with special handling
- Supports IERP (Integrated Enterprise Resource Planning) flag for specialized exports

#### History Export
- Exports proposal history data from Salesforce
- Creates Excel files with multiple sheets for different history types
- Each sheet contains detailed history records

#### PFX Export
- Exports PFX (likely "Proposal/FX") data based on proposal ID and view parameters
- Handles external unmapped data when available
- Creates Excel files with the exported data

### 3. Background Processing

All exports are processed as background jobs to prevent timeout issues:

- Jobs are dispatched by the SalesforceController
- Progress is tracked in database tables
- Status updates are logged for user visibility

### 4. File Storage

Exported files are stored and shared via Google Drive:

- `GoogleDriveHelper` handles file upload and sharing
- For non-final exports, files are shared with public read access
- Download links are stored in the database for user access

## Database Schema (Inferred)

The application uses several database tables to track export jobs:

1. **Billing Export Table** (name from env: `BILLING_EXPORT_TMP_TABLE`)
   - Stores invoice export jobs and their status
   - Tracks: user information, period details, billing status, search terms, progress

2. **History Export Table** (name from env: `HISTORY_EXPORT_TMP_TABLE`)
   - Stores history export jobs and their status
   - Tracks: user information, proposal ID, progress

3. **PFX Export Table** (name from env: `PFX_EXPORT_TMP_TABLE`)
   - Stores PFX export jobs and their status
   - Tracks: user information, proposal ID, view details, progress

## Authentication and Security

1. **Salesforce Canvas Authentication**
   - Uses signed requests with HMAC SHA-256 validation
   - Different consumer secrets for different export types
   - Session validation for continued user interaction

2. **Process Token Authentication**
   - Custom token-based authentication for export process pages
   - Validates user access to export results

## API Integration

### Salesforce SOAP API

The application uses SOAP clients to connect to Salesforce services:

1. **PFX_BillingReportService**
   - Used for invoice exports
   - Provides methods for report headers, data retrieval, and cumulative information

2. **PFX_HistoryReportService**
   - Used for history exports
   - Provides methods for retrieving various history types

3. **PFX_ExportViewService**
   - Used for PFX exports
   - Provides methods for headers, data, and external unmapped data

### Google Drive API

- Used for file storage and sharing
- Supports uploading files, creating folders, and managing access permissions
- Provides shareable download links for exported files

## Configuration

The application uses various environment variables for configuration:

- Database connection details
- Salesforce WSDL endpoints and credentials
- Consumer secrets for Canvas integration
- Google Drive authentication and folder IDs

## Flow of Operation

1. **Initiation**:
   - User clicks an export button in Salesforce
   - Salesforce sends a signed request to the application via Canvas

2. **Authentication**:
   - `SalesforceController` receives the request
   - `SignedRequest` validates the signature
   - User session is established

3. **Job Creation**:
   - Export parameters are extracted from the request
   - A record is created in the appropriate database table
   - A background job is dispatched

4. **Processing**:
   - Job connects to Salesforce using the session token
   - Data is retrieved in chunks to avoid memory issues
   - An Excel file is generated with the data
   - Progress is updated in the database

5. **File Storage**:
   - Completed Excel file is uploaded to Google Drive
   - File is shared with appropriate permissions
   - Download link is stored in the database

6. **Result Delivery**:
   - User is redirected to a process page with the status
   - Once complete, download link is provided
   - Error handling for failed exports

## Error Handling

The application includes comprehensive error handling:

- Database logging of errors
- User-friendly error messages
- Detailed server logging
- Status tracking for exports

## Code Structure Best Practices

The codebase demonstrates several best practices:

- Separation of concerns with controllers, models, and jobs
- Interface-based design for file storage
- Inheritance for shared functionality
- Comprehensive logging
- Background processing for long-running tasks
- Secure token-based authentication
