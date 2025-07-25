/* 
  PagerDuty User Definition
  Ref: https://www.terraform.io/docs/providers/pagerduty/r/user.html
*/

/* 
  Support
*/
resource "pagerduty_user" "noah_cooper" {
  name  = "Noah Cooper"
  email = "noah_cooper@company.com"
  role  = "limited_user"
}

/* 
  Operations
*/
resource "pagerduty_user" "paul_miller" {
  name  = "Paul Miller"
  email = "paul_miller@company.com"
  role  = "limited_user"
}

/* 
  IT Management
*/
resource "pagerduty_user" "ronald_green" {
  name  = "Ronald Green"
  email = "ronald_green@company.com"
  role  = "limited_user"
}



/* 
  Executive Stakeholders
*/
resource "pagerduty_user" "julie_morgan" {
  name  = "Julie Morgan"
  email = "julie_morgan@company.com"
  role  = "restricted_access"
}
