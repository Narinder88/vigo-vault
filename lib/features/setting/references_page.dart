import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ReferencesPage extends StatelessWidget {
  const ReferencesPage({super.key});

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 20.0, bottom: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _bodyText(String text) => Text(text);

  Widget _bulletLink({required String label, required String url}) {
    return InkWell(
      onTap: () => launchUrlString(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '• $label: ',
                style: const TextStyle(color: Colors.black87),
              ),
              TextSpan(
                text: url,
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Health References'),
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('About BMI Section'),
            _bodyText(
              'BMI ranges and definitions are based on the Centers for Disease Control and Prevention (CDC) and World Health Organization (WHO) classifications.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Sources:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            _bulletLink(
              label: 'CDC Adult BMI',
              url:
                  'https://www.cdc.gov/bmi/faq/?CDC_AAref_Val=https://www.cdc.gov/healthyweight/assessing/bmi/adult_bmi/index.html',
            ),
            _bulletLink(
              label: 'WHO BMI Classification',
              url:
                  'https://www.who.int/news-room/fact-sheets/detail/obesity-and-overweight',
            ),
            _sectionTitle('About Dark Chocolate Intake'),
            _bodyText(
              'Recommendations regarding dark chocolate consumption are based on research from Harvard T.H. Chan School of Public Health and the Cleveland Clinic.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Sources:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            _bulletLink(
              label: 'Harvard',
              url:
                  'https://www.hsph.harvard.edu/nutritionsource/food-features/dark-chocolate/',
            ),
            _bulletLink(
              label: 'Cleveland Clinic',
              url:
                  'https://health.clevelandclinic.org/dark-chocolate-health-benefits/',
            ),
            _sectionTitle('Steps / Calories (if used)'),
            _bodyText(
              'Step and calorie burn information is based on general estimations from Mayo Clinic.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Source:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            _bulletLink(
              label: 'Mayo Clinic',
              url:
                  'https://www.mayoclinic.org/healthy-lifestyle/weight-loss/in-depth/walking/art-20046261',
            ),
          ],
        ),
      ),
    );
  }
}
