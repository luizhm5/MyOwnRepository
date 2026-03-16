# ad-tech-invoice-export

## Testing
1. Install dependencies with `composer install`
2. Copy `.env.example` to `.env` and provide correct values for desired environment
3. Run development server with `php artisan serve`

## Deploying for Production

1. Remove all contents from deployment directory if it already exists
2. Clone this repository into deployment directory
3. Run `$ composer update`
4. Copy the `.env.example` file to `.env` and provide correct data for environment variables in this file.

URL for SalesForce Canvas integration: https://**app**/salesforce_canvas

For example: https://ad-tech-dev.weather.com/ev/invoice_export/salesforce_canvas

## System Requirements

    Apache server >= 2.4.0
    MySQL server >= 5.7.0
    PHP >= 8.2
