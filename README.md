# UserVoice to Aha Migration w/ Salesforce
When trying to migrate my company's data from UserVoice to Aha, I ran into a couple issues; specifically, Aha's automatic migration doesn't preserve the existing Salesforce links, and UserVoice's Salesforce integration adds every single Salesforce contact to UserVoice (even if they haven't interacted with UserVoice).

I wanted a way to selectively migrate contacts from UserVoice to Aha, as well as preserve the feature requests' links to Salesforce.

_Note: UserVoice calls feature requests "suggestions" and Aha calls feature requests "Ideas"—I will just be using the term "feature requests" in the README to avoid confusion._

## What It Does
Running this script will do a few key things:

- Migrate all users from UserVoice that have submitted or voted on a feature request (and maintain their link to their Salesforce Account).
- Migrate all feature requests that haven't been deleted or are marked as spam.
- Migrate all votes on feature requests.
- Migrate all comments on feature requests.
- Migrate all proxy votes (known as "feedback requests" on UserVoice), preserving their links to Salesforce.
- Merge any feature requests in Aha that were previously merged in UserVoice.

## Getting Started

# Prerequisites
In order to run this script successfully, you'll need to do a couple things:

- Add the Salesforce integration to Aha and allow time for SF Accounts to migrate over to Aha.
- Create an Aha Idea Portal that will be associated with your migrated ideas.
  - Turn off email notifications on the Idea Portal to prevent spamming your customers with a bunch of "thank you for submitting an idea!" emails when the feature requests are migrated over.
  - Enable SSO on your portal (doesn't have to actually work) to prevent spamming your customers with a bunch of "create a password" emails when they are migrated over.
- Create a fallback user that will be used in the instance that a contact doesn't exist
  - The fallback user should exist in Salesforce and also as an Aha portal user.
- Copy `config-example.yml` to `config.yml` and fill out the configuration details (see section below).


# Configuration
Copy `config-example.yml` to `config.yml` and fill out the following configuration items in `config.yml`:

| Key | Description |
| --- | --- |
| `fallback_user` | email of the fallback user configured in your SF and Aha Idea Portal instances |
| `email_subdomain` | your company's email subdomain |
| `uv_api_key` | API key for UserVoice |
| `uv_api_secret` | API secret for UserVoice |
| `uv_subdomain` |  your UserVoice subdomain (e.g. `mycompany` if your UserVoice domain is `mycompany.uservoice.com`) |
| `aha_api_key` | API key for Aha |
| `aha_subdomain` | your Aha subdomain (e.g. `mycompany` if your UserVoice domain is `mycompany.aha.io`) |
| `aha_idea_portal_id` | the ID of the Aha Idea Portal with which you'd like your feature requests to be assoociated |
| `aha_product_id` | the product id of the Aha workspace into which you'd like your feature requests to be added. Also known as the "prefix" under Account Settings -> Customizations -> Workspaces -> Edit Workspace. |
| `aha_sf_integration_id` | the id of the Salesforce integration in Aha. You can grab this by navigating to the Salesforce integration in Aha and pulling it from the URL (e.g. `12345` if the URL is `https://mycompany.aha.io/settings/integrations/12345/enabled`) |
| `aha_default_status` | The default status that feature requests will have when they are migrated to Aha. Can be overridden by the `status_map` configuration. |
| `aha_default_category` | The default category that feature requests will have when they are migrated to Aha. Can be overridden by the `category_map` configuration. |
| `status_map` | a key-value map where the key is the feature request's UserVoice status and the value is the Aha status you want the feature request to have after migrating. |
| `category_map` | a key-value map where the key is the feature request's UserVoice category and the value is the Aha category you want the feature request to have after migrating. |
| `sf_subdomain` | your Salesforce subdomain (e.g. `mycompany` if your Salesforce domain is `https://mycompany.lightning.force.com/`) |
| `sf_access_token` | a Salesforce access token. You can generate a Salesforce access token by installing the Salesforce CLI and following the instructions here: https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/quickstart_oauth.htm?q=auth |